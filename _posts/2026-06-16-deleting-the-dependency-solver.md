---
layout: post
title: "I deleted the dependency solver"
date: 2026-06-16
author: Gareth Stokes
---

Every package manager has a component its users dread. In Haskell it's the version solver: the part of cabal-install that takes the version ranges scattered across your dependency graph and searches for one assignment that satisfies all of them. When it works you never think about it. When it fails you get a page of text about incompatible bounds on a package three levels down that you've never heard of, and your afternoon is gone.

[zinc](https://github.com/garethstokes/zinc) is a Haskell build tool that doesn't have one. It started as a question I wanted a real answer to: how far can you get without a solver at all? Not "a faster solver" or "a friendlier solver" but none, and see where that runs out.

So the whole design rests on a single decision. zinc is git-native and Nix-assisted, and it drops the solver entirely. Dependencies are git repositories pinned by content hash. Each package name resolves to exactly one ref across the workspace. Nothing searches a constraint space, so there are no solver errors. The price is that a real conflict between two packages doesn't get resolved for you. You resolve it once, by hand, and the choice gets frozen into the lockfile. I think that trade is worth making, and most of this post is me checking how far it actually goes before it breaks.

One other thing shaped the work, and I'll mostly keep it in the background: zinc was built alongside an agent, with every commit tied to a tracked issue and the design written down before the code. What that was good for had less to do with generating code than with keeping the no-solver rule honest across a couple hundred commits. The stories below are where that pressure shows up.

## Where zinc sits

This isn't unprecedented. zinc takes one more step down a road Go already walked.

| | Source of packages | Pinned by | Selection algorithm | Multiple versions of one package? |
|---|---|---|---|---|
| Cargo | central registry (crates.io) | hash in `Cargo.lock` | full semver solver | yes, incompatible majors coexist |
| Go | decentralized git modules | hash in `go.sum` | Minimal Version Selection | no, one per module |
| zinc | decentralized git | hash in `zinc.lock` | none | no, one ref, ever |

Cargo is the maximalist version. It runs a real solver over semver ranges, and the same crate can appear several times in one build at different major versions. Go is the interesting middle: git-native, hash-pinned, no SAT solver, but it keeps a selection algorithm called Minimal Version Selection that computes the lowest version of each module compatible with everyone's stated minimums. MVS isn't a solver in Cargo's sense, but it still chooses versions for you.

zinc drops that last piece too. No algorithm picks versions. The rule is blunt: one ref per package name, a root-level override wins any disagreement, and otherwise the most recently referenced ref does. A tag like `v2.2.3.0` is just how you pick a commit the first time you add a dependency. Once it's written to `zinc.lock` it's a SHA plus a content hash, and the version string has done its only job. That's the entire resolution model.

The fair question is what happens when real packages don't cooperate, so that's where I'll start.

## Argument 1: no solver survives reality, because versions describe but never decide

The failure that ought to sink the whole idea looks like this. You add `effectful`, a popular effects library. The build runs for a while, then GHC stops on:

```
ErrorT not in scope
```

The error is in `monad-control`, a package you didn't ask for, pulled in by something else you didn't ask for. It names a type that left the ecosystem years ago. There's no version number in it and nothing obvious to grep for.

The cause is a familiar Haskell papercut. `monad-control`'s newest release tag declares `build-depends: transformers < 0.6`. The toolchain ships `transformers 0.6.1.0`. `ErrorT` was removed in `transformers 0.6`. So the package's latest tagged release can't compile against the compiler it's being built with, because the maintainers fixed the bound on their main branch and never cut a new release. cabal's solver gets around this by finding some other set of versions that works. zinc has no solver to get around with, so it has to notice the problem directly.

This is the part the bet depends on. zinc reads that `< 0.6` bound, but it reads it only to explain the failure, never to choose anything. A small detector parses the dependency's `.cabal` and checks each boot-library bound against the version the toolchain actually ships. The code that does this carries a comment reminding the next person that the bound is for diagnostics only and must never feed back into resolution. zinc still pins a commit, not a version range. Let a range start influencing what gets selected and you've rebuilt the solver, so it isn't allowed to.

What you see in place of `ErrorT not in scope` is this:

```
ZINC_DEP_BOOT_CONFLICT (exit 3)
  dependency's tag conflicts with a toolchain boot library
  monad-control requires transformers <0.6, but the toolchain ships transformers 0.6.1.0
  hint: its newest release tag is stale; pin it forward to a commit whose
        transformers bound admits 0.6.1.0  ([dependencies.monad-control] rev = "...")
```

Two details deserve more honesty than my first pass gave them.

The forward-pin suggestion is a hint, not a computed answer. Right now zinc clones the dependency's default branch, checks whether the tip relaxes the bound, and offers that commit if it does. That's coarse. The tip might be hundreds of commits past the stale tag with a pile of unrelated changes, and it only checks the bound rather than trying a compile. Finding the smallest commit that actually fixes the bound, by bisecting or by walking the `.cabal` file's own history, would be better. It's filed as future work, not something I'm claiming now. Even the coarse version is the rule working as designed, though: zinc proposes a commit, you decide, your choice gets frozen as explicit state. The tool never resolves anything silently.

And this wasn't a one-off. Pin `monad-control` forward and the build moves exactly one step before hitting the next stale tag, `strict-mutable-base`, whose latest release is older than what `effectful` needs and is missing a function added later. Same shape, same fix. The second independent case is what convinced me it deserved a real diagnostic instead of a workaround.

So the bet holds, with a caveat I'd rather state than gloss over. Deleting the solver doesn't make conflicts go away; it means you can't hide them. A solver would have searched quietly past this one. zinc can't, so the most it can do is turn the worst error in the build into the most readable one, give you somewhere to start, and let you make the call.

## Argument 2: the conflict that's left is permanent, and that's the right thing

There's a question lurking under the last story. If a stale version bound is what set the whole mess off, isn't the no-solver design just borrowing trouble that cabal already handles?

Most of that particular trouble is on loan from the old ecosystem, and it gets paid back as the ecosystem changes. The boot-conflict diagnostic exists only because upstream packages publish cabal version bounds. A zinc-native package declares its dependency as `depends = ["transformers"]` with no bound at all and gets whatever the toolchain ships, because boot libraries come with the compiler and are never fetched. In a world where packages described themselves to zinc instead of to cabal, the `transformers < 0.6` problem couldn't occur, because there'd be no bound to go stale. The diagnostic is a bridge to the packages that exist today, and it fires less the more of them describe themselves natively. I'm fine building something that becomes less necessary over time.

One kind of conflict doesn't go away, though, and it's worth being clear that zinc has no plan to make it disappear. If package A wants `bytestring` at one ref and package C wants it at another, the one-ref-per-name rule forces a single choice. With no solver, you make that choice. That's not a gap in the design; it's the design. The bet is that this situation is rare in practice and that a human picking a ref, once, with the conflict spelled out, beats a solver picking one silently and being wrong in a way you discover three hours into a build.

This is also where the most interesting road-not-taken sits. You could imagine computing a forward-pin properly instead of guessing the branch tip: find the minimal commit of a package whose boot-library bounds are all satisfiable against the toolchain. That sounds like Go's MVS, and it rhymes with it, but it's a different problem. MVS searches a space where every version across the graph is negotiable. Here the toolchain ships exactly one version of each boot library, a fixed constant, so picking the smallest compatible commit is a deterministic computation rather than a search. No SAT, no negotiation, just an answer.

That would be a genuine selection algorithm, and adopting it would mean letting a bound influence what gets chosen, which is the line Argument 1 spent its whole length defending. So I've drawn the fork deliberately rather than pretending it isn't there. The plan is to expose that computation as a tool you run when you want a better forward-pin suggestion, and never as something that resolves on its own. The bound can compute a hint for you; it still doesn't get to decide. That keeps the property that matters: every ref in your lockfile is there because a person put it there.

## Argument 3: driving GHC directly means inheriting a long tail, and that's the honest cost

Dropping the solver is the headline, but the same instinct, do it ourselves rather than delegate, applies to the build itself. zinc drives `ghc --make` directly and doesn't run Cabal's build machinery. The benefit is a fast, legible build with no `Setup.hs` indirection. The cost is real, and `network` is where you feel it.

`network` is the package the entire HTTP and TLS stack sits on, so it had to work, and getting it to compile took four separate fixes that cabal performs for you without comment. The preprocessor needed the package's own include directories threaded through to find a bundled header. A `build-type: Configure` step had to be run from the Hackage sdist, because the git checkout doesn't ship the generated `./configure`. The preprocessor was running over Windows-only modules on Linux and choking, so it had to be scoped to the modules cabal's conditionals would actually select. And the `MIN_VERSION_*` macros that GHC generates for the main compile weren't reaching the preprocessor's C step, so a header had to be emitted and included by hand. None of this is clever. It's the unglamorous tax you take on when you stop delegating to cabal's builder, and the only honest thing to say about it is that the tax is finite and `network` builds clean now. I'm including it because a build tool that only works on toy fixtures isn't a build tool, and skipping the boring part would be the dishonest way to tell this story.

## Argument 4: the toolchain work can be clean even when the envelope is bounded, if the boundary fails fast

The last story is the one with an actual demo at the end. `zinc build --target wasm32-wasi` cross-compiles a workspace to WebAssembly, and it does the fiddly parts with no setup from you. It provisions the GHC wasm cross-compiler through the `ghc-wasm-meta` flake, produces either a WASI command module or a browser reactor module depending on one setting in your manifest, and for the reactor case it generates the JavaScript FFI glue that lets a browser call into the module.

There's a runtime trap in here worth knowing about even if you never touch zinc, because it's a property of GHC's wasm output rather than anything zinc invented. A reactor module's runtime isn't started by the wasm `_initialize` call alone; the host has to call `hs_init` once before any exported Haskell function runs, or the first call aborts with `newBoundTask: RTS is not initialised`. zinc always exports `hs_init` from a reactor so the module is loadable, and the proof-point is a real one: a `miso` front-end, a virtual-DOM counter, compiled to wasm and clicked in a browser.

Now the part you actually need to plan around. The toolchain plumbing is solved, but the set of packages that can cross-compile is bounded, and zinc tells you so up front instead of failing cryptically at link time. Pure Haskell works. A package with its own C sources works. A package that links an external system library does not, because there's no prebuilt wasm build of that C library to link against, and you get a typed `ZINC_WASM_UNSUPPORTED` with the package named rather than a wall of linker output. So the practical advice is concrete: if you're building a mostly-Haskell front-end, try it today; if your dependency closure reaches for `zlib` or similar, you'll hit the wall immediately and know exactly why. The boundary moves outward over time, and the gaps that move it, like supporting external system libraries, are tracked as their own work rather than hidden behind an optimistic README.

## What actually carried the work

Two things land together at the end. The first is that `zinc build` builds zinc. Self-hosting was the definition of done from the start, because it's the one test that exercises the resolver, the `.cabal` reader, the Nix environment, the build driver and the cache against real packages at once. The second is that everything zinc does is built to be driven by a program as easily as by a person: every command emits a JSON envelope, every failure carries a stable `ZINC_*` code and a category exit code, and there are no interactive prompts to hang on. The tool an agent helped build is a tool an agent can run, and that wasn't a slogan, it was the constraint that made the agent useful in the first place.

That's the part I'd point at for anyone building real software this way. The leverage wasn't in generating code quickly. It was in two older disciplines that an agent happens to reward more than a human collaborator does. Writing the design down before the code, so the no-solver rule had somewhere to live and something to be checked against. And designing for inspection, so every decision the tool makes lands as explicit, frozen state you can read back later. The slogan I kept coming back to was explicit state, not explicit effort, and it turned out to describe the working relationship as much as the lockfile.

The bet went further than I expected. From the first commit to a self-hosting build, wasm cross-compilation and zero-downtime deploys took about two weeks. The solver is still gone, and I haven't yet hit the place where I wish it back.
