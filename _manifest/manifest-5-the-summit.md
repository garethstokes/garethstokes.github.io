---
layout: post
title: "a shadow in the world of types"
author: Gareth Stokes
permalink: /manifest/the-summit/
series: manifest
part: 5
of: 6
---

{% include series-nav.html %}

<figure>
  <img src="/assets/images/hero-value-and-type-shadow.svg" alt="Two parallel tracks. On the value track, get fetches an entity and with loads its posts. On the type track below, its shadow, the load-set list goes from empty to the one holding posts as with runs. The two tracks move in step, tied by a dashed line.">
  <figcaption>The value runs along the top; its load-set runs along the bottom as a shadow in the types, and <code>with</code> moves both at once.</figcaption>
</figure>

The value reads and writes cleanly now, but it stops at the edge of its own row. A
relationship is not a column. `user.posts` is a separate table and a separate query, so it
cannot sit on the record the way `userName` does; it has to be fetched on its own. Which
leaves a question the moment you write the accessor. If someone reads `posts` on a user
whose posts were never loaded, what comes back? A runtime `Nothing` is one answer, and a
poor one, because it pushes the failure to the place the data is used rather than the place
the mistake was made. The quieter answer is worse: hand back an empty list, and the caller
reads "this user has no posts" off a user who has plenty. You would rather the compiler stop
you, with a sentence you can act on, before the program ever runs.

Everything up to here has been a functor doing its work on values: a record wrapped in a
chosen `f`, a function mapped through it, the bare value falling out the other side. The
same idea has a home one level up. A type family is a function whose arguments and result
are types, run by the compiler while it checks your program. `Field` was already one of
these in part 2, taking `Identity` and a marker to a bare `Int`. Lift the load problem into
that setting and the bookkeeping becomes a value the compiler computes for you.

So manifest records what has been loaded as a list of relation names, a type-level list like
`'["posts"]`, and carries it as a phantom parameter on a wrapper around the value:

```haskell
data Ent (loaded :: [Symbol]) a =
  Ent { entVal :: a, entRels :: RelMap }

-- a fresh fetch has nothing loaded:
get :: Key a -> Db (Maybe (Ent '[] a))

-- with accumulates one name into the set:
with
  :: HasRelation a name
  => Strategy name
  -> Ent l a
  -> Db (Ent (Insert name l) a)
```

The `loaded` parameter holds no values; it is there only for the compiler to read. A fresh
fetch is `Ent '[] a`, the empty list standing for "nothing loaded." `with` does two things
at once, one in each world. At the value level it runs the query and stores the rows in
`entRels`. At the type level it inserts the name into the list, `Insert name l`, so the
returned type carries one more name than the one that went in. Chain two `with` calls and
the list carries both names; the inserts stack the way function composition did at the start
of the series, now playing out on types. What the accessor checks is only membership, whether
a name is in the list and never where it sits, so this is a membership list rather than an
ordered set, and the order the names arrive in does not matter.

The accessor is where the set earns its keep. `rel` reads a relation off a loaded entity, and
its `Member` constraint means it only typechecks when the load-set actually holds the name:

```haskell
do mu <- getEnt (Key 1)              -- Maybe (Ent '[] User)
   for_ mu $ \u -> do
     u' <- with (selectin #posts) u  -- Ent '["posts"] User
     let ps = rel #posts u'          -- ps :: [Post], total
     pure ()
```

Move the `rel #posts` up a line, onto the `Ent '[] User` before `with` has run, and
`Member "posts" '[]` has no way to hold, so the program does not compile. Once `with` has put
`"posts"` in the set the read is total: the type proves the data is there, and the empty list
and the spurious `Nothing` are both gone, ruled out before the program runs.

<figure>
  <img src="/assets/images/fig-unloaded-error.svg" alt="Reading posts on an entity that never loaded them fails to compile. In place of a wall of type-list internals, shown muted and struck out, manifest prints one written sentence in the accent colour telling you the relation is not loaded and how to load it.">
  <figcaption>An unloaded read stops at compile time, and the message is a sentence you can act on, not the type-list internals behind it.</figcaption>
</figure>

Type-level work is exactly where Haskell's error messages turn into a screen of internals
nobody asked for, so the honest part of this design is the upkeep that keeps them legible.
manifest gives `Member` an `Unsatisfiable` instance whose only output is a written sentence:
"Relation 'posts' is not loaded on this User. Add `with (selectin #posts)`, or call
`load #posts u`." The set tracks the Symbol names of relations, never the `Post` or
`Comment` types behind them, so those stay out of every message. The compiler is only ever
asked whether a name belongs to a set, never to prove two sets equal, which is the question
that produces the unreadable output. The phantom rides on `Ent` and nowhere else: not on the
bare value, not on a query, not on a `Db` action. And the floor is always one call away.
`load #posts (entVal u)` hands back the same posts with none of the type-level apparatus, so
the load tracking is a ceiling you opt into over a plain floor you can always drop to.

Which brings the series back to where it started. The first page set this signature down
with no explanation and asked you to sit with it:

```haskell
with
  :: HasRelation a name
  => Strategy name
  -> Ent l a
  -> Db (Ent (Insert name l) a)
```

Every character of it is now plain. `HasRelation a name` is the constraint that `a` has a
relation called `name`. `Strategy name` is how that relation gets fetched. `Ent l a` is the
value with its load-set `l`, and `Ent (Insert name l) a` is the same value with `name` added
to that set: the type family computing the new shadow as the value gains its posts. The whole
climb was learning to read one line.

There is one thing left, and it is not another rung. The machinery is built and the
signature reads cleanly, which only sharpens the question underneath all of it: what was the
category theory actually buying, against a plainer ORM that skips it? That account comes last.

---

{% include series-nav.html %}
