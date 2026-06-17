---
layout: post
title: "the math under manifest"
description: "The category theory behind manifest, a Haskell ORM, built up from first principles one step at a time."
author: Gareth Stokes
permalink: /manifest/
---

This is how to define a user in manifest, a database library for Haskell:

```haskell
data UserT f = User
  { userId    :: Field f (Pk Int)
  , userName  :: Field f Text
  , userEmail :: Field f (Nullable Text)
  }
```

and this is the type of the function that loads one together with its posts:

```haskell
with
  :: HasRelation a name
  => Strategy name
  -> Ent l a
  -> Db (Ent (Insert name l) a)
```

That can seem pretty strange, but hopefully it will all make sense by the time you have read
this. We build up to it from simple maths, one step at a time, so that each piece makes
sense before the next one arrives.

<figure>
  <img src="/assets/images/hero-the-climb.svg" alt="A ladder whose rungs from bottom to top read functions and composition, functors, higher-kinded types, applicative and profunctor, monads, and type families, with an arrow climbing toward the top where the opening signature becomes readable.">
  <figcaption>From functions to type families, one rung at a time, until the opening signature reads itself.</figcaption>
</figure>

Most writing about code like this goes one of two ways. It walks the syntax token by token,
which leaves you able to recite the type but not to write it; or it waves a hand and calls
the whole thing category theory, which leaves you with less. This series does what a maths
teacher asks for instead, and shows the working. Functions first, then functors, then
higher-kinded types, then the codecs and monads and type-level machinery stacked on top,
each one earned before the next is introduced.

There is a reason the working is worth showing, and it is the reason manifest exists.
Haskell has had excellent type-safe SQL libraries for years, but it never had the thing
SQLAlchemy gives Python: a session you hand an edited object to, which works out the minimal
UPDATE for whatever you changed. Nobody built it because the obvious design mutates the
object in place so the session can watch it, and a Haskell value will not be mutated. So
every idea that follows is a piece of mathematics standing in for a mutation you are not
allowed to make. Take away the ability to reach into a value and change it, and category
theory is what you reach for to get the same work done honestly.

If Haskell itself is new to you, the [prelude](/manifest/prelude/) covers how to read the
type signatures first. The path then runs from a plain record to that signature, in six
steps:

1. [a record that's three things at once](/manifest/the-call/) — one declaration that is a table, a row, and a query (functor and higher-kinded types)
2. [making the markers disappear](/manifest/the-threshold/) — getting a clean `Int` back (the Identity functor)
3. [reading a row without a ceiling](/manifest/the-trials/) — decode and encode from one description (applicative and profunctor)
4. [the session that can't see your edit](/manifest/the-ordeal/) — change tracking on a value you cannot mutate (the monad and the snapshot-diff)
5. [a shadow in the world of types](/manifest/the-summit/) — a missing relation as a compile error (type-level functions)
6. [the working, complete](/manifest/the-return/) — the signature, now obvious (Generics ties it together)
