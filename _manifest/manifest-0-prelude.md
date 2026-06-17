---
layout: post
title: "a prelude: reading the types"
author: Gareth Stokes
permalink: /manifest/prelude/
---

<nav class="series-nav">
  <span class="series-nav__prev"><a href="/manifest/">← the journey</a></span>
  <span class="series-nav__mid">prelude</span>
  <span class="series-nav__next"><a href="/manifest/the-call/">a record that's three things at once →</a></span>
</nav>

<figure>
  <img src="/assets/images/hero-read-a-signature.svg" alt="The signature add followed by two colons and Int arrow Int arrow Int, with the first two Int labelled argument and the final Int labelled the result.">
  <figcaption>The part after the final arrow is the result; everything before it is an argument.</figcaption>
</figure>

The parts that follow lean on small pieces of Haskell, types like `map3 :: (a -> b -> c -> r) -> Decoder a -> ...`. The ideas are the point, and the punctuation should not get in the way of them, so this page is the whole alphabet. Everything after it is about what you can spell with it. Skip ahead if you already read Haskell.

A signature gives a name, two colons, and a type. `not :: Bool -> Bool` reads "not has type Bool to Bool": it takes a `Bool` and gives a `Bool` back. The arrow `->` is the function arrow, and it is most of the punctuation you need:

```haskell
not     :: Bool -> Bool       -- a Bool in, a Bool out
add     :: Int -> Int -> Int  -- two Ints in, an Int out
reverse :: [a] -> [a]         -- a list of any a, reversed
```

When a function takes more than one thing, the arrows chain. Read the type after the final arrow as the result, and everything before it as the arguments, so `add` takes two `Int`s and returns one. Under the hood every Haskell function takes a single argument and returns the rest, which is why it is arrows rather than a comma-separated list, but reading it as arguments-then-result will never lead you wrong.

A lowercase name in a type, like the `a` in `reverse`, is a stand-in for any type at all. So `reverse` works on a list of numbers or a list of strings without caring which. When a later part writes a signature full of `a`, `b`, `c`, and `r`, those are simply "some types, your choice."

A type wrapped in parentheses that has its own arrow inside is a function being passed in as an argument. That is the shape of the signature this prelude exists for:

```haskell
map3 :: (a -> b -> c -> r)
     -> Decoder a -> Decoder b -> Decoder c -> Decoder r
```

The first argument, `(a -> b -> c -> r)`, is itself a three-argument function, the thing that builds the result. The three after it are decoders. The whole line reads: given a builder of three things and three decoders for those things, hand back a decoder of the finished result.

Applying a function to a value needs no brackets. Where maths writes `f(x)`, Haskell writes `f x`. Nesting reads the way it always has: `f (g x)` is the familiar `f(g(x))`, do `g` first and then `f`. There is a shorthand for that chaining, a dot, so that `(f . g) x` and `f (g x)` mean the same thing.

<figure>
  <img src="/assets/images/fig-fgx-composition.svg" alt="The value x goes into the function g, the result g x goes into the function f, and out comes f of g of x.">
  <figcaption>Composition is just nesting: x through g, then that result through f.</figcaption>
</figure>

One last shape to recognise. Symbols like `<$>` and `<*>` are ordinary functions written between their arguments, the way `+` sits between two numbers. Both turn up in the parts ahead; for now it is enough to know they go between values and are read left to right.

That is the whole notation the series rests on. Everything from here is about the ideas it spells, starting with a single record that has to be three things at once.

<nav class="series-nav">
  <span class="series-nav__prev"><a href="/manifest/">← the journey</a></span>
  <span class="series-nav__mid">prelude</span>
  <span class="series-nav__next"><a href="/manifest/the-call/">a record that's three things at once →</a></span>
</nav>
