---
layout: post
title: "reading a row without a ceiling"
author: Gareth Stokes
permalink: /manifest/the-trials/
series: manifest
part: 3
of: 6
---

{% include series-nav.html %}

<figure>
  <img src="/assets/images/hero-codec-both-directions.svg" alt="A single Codec box wraps one column. A decode arrow runs from the column's bytes out to a User value; an encode arrow runs from the User value back into the column. One description carries both directions.">
  <figcaption>One <code>Codec</code> holds a column's decode and encode together: read going right, written coming back left.</figcaption>
</figure>

A row comes back from Postgres as a flat list of column byte-values, in order, and you have a `User` to build out of them. The value the last part handed you reads cleanly once it exists; the trouble is getting it to exist from a `[SqlParam]` that knows nothing about records. Something has to walk that list left to right, claim the first column as an `Int`, the next as `Text`, and assemble the pieces into the constructor.

The approach you would borrow fixes the arity in advance, the way [Elm's JSON decoders](https://package.elm-lang.org/packages/elm/json/latest/Json.Decode) and [Lune](https://github.com/garethstokes/lune) do. To build a three-field value you reach for a three-argument combinator, where a `Decoder a` is anything that reads an `a` out of the columns:

```haskell
map3 :: (a -> b -> c -> r)
     -> Decoder a -> Decoder b -> Decoder c -> Decoder r

userDecoder = map3 User (col int) (col text) (col (nullable text))
```

`map3` takes the constructor and exactly three decoders, runs them left to right, and applies. It works until you add a fourth field; then you need `map4`, with a fourth decoder argument, and a fifth field wants `map5`. No single function can take however many decoders a record happens to have, so a library ships a finite ladder, `map2` through `map5` or so, and your record cannot be wider than the longest rung someone bothered to write. There is a quieter cost on top: you write the decoder by hand and the matching encoder somewhere else, and the two drift apart the first time a column's type changes and only one side gets the memo.

The way past the arity ceiling is the applicative functor. A plain functor maps one function over one structure and stops there. An applicative lets you hold a function that itself sits inside the structure and feed it arguments, one `<*>` at a time, each argument also inside the structure. So you start with the constructor lifted in, `User <$> col int`, and keep applying:

```haskell
User <$> col int <*> col text <*> col (nullable text)
```

That chain is as long as the record is wide. There is no `mapN` because `<*>` is the only combinator and it composes with itself forever. manifest's `RowDecoder` is exactly this applicative: each decoder is a function from the remaining columns to a value plus the columns it did not consume, threaded through `Either` so a type mismatch stops the walk:

```haskell
newtype RowDecoder a =
  RowDecoder { runRowDecoder :: [SqlParam] -> Either DecodeError (a, [SqlParam]) }

instance Functor RowDecoder where
  fmap f (RowDecoder g) = RowDecoder $ \cs -> do
    (a, rest) <- g cs
    pure (f a, rest)

instance Applicative RowDecoder where
  pure x = RowDecoder $ \cs -> Right (x, cs)
  RowDecoder f <*> RowDecoder g = RowDecoder $ \cs -> do
    (h, cs')  <- f cs
    (a, cs'') <- g cs'
    pure (h a, cs'')
```

The `<*>` is where the left-to-right consumption lives: run the function-decoder over the columns, hand what is left to the argument-decoder, combine the two results. `pure` consumes nothing and passes the list along untouched. Width stops being a problem the moment the structure, not a fixed combinator, carries the count.

An applicative is still a functor. It keeps everything a functor has, including the two laws from the first part, and adds `pure` and `<*>` on top. Those two earn four more laws, and all of them say the same kind of thing the functor laws did: `pure` and `<*>` shuffle values around without disturbing the structure. A wrapped identity changes nothing, wrapping commutes with application, a `pure` argument does not care which side runs first, and `<*>` regroups freely:

```haskell
pure id <*> v              = v
pure f <*> pure x          = pure (f x)
u <*> pure y               = pure ($ y) <*> u
pure (.) <*> u <*> v <*> w = u <*> (v <*> w)
```

That last one is what the chain leant on: because `<*>` regroups freely, `User <$> col int <*> col text <*> ...` means one thing no matter how wide the record gets.

That handles reading. Writing wants the mirror, and whether the two can share one description comes down to what kind of thing each one is. A decoder produces an `a`; vary the `a` and the decoder varies with it, which makes it covariant in `a`. An encoder consumes an `a`; vary the `a` and the encoder varies against it, which makes it contravariant. A profunctor is both at once, covariant on its output and contravariant on its input, and `dimap f g` is how you adapt one: `f` pre-composes on the input you consume, `g` post-composes on the output you produce.

manifest's `Codec` is a profunctor in this sense, built on `Data.Profunctor` and its `dimap`, `lmap`, and `rmap`. One `Codec` value is a single per-column codec, holding the decode, the encode, the SQL type, and the nullability together, so the two directions of a column have nowhere to drift apart; the column's name lives in the table metadata, not the codec. That settles the round trip the series promised at the start, moving rows in and out, in one value per column — over a single type today, with the sharper version, where read and write are different types, still ahead.

<figure>
  <img src="/assets/images/fig-read-write-types.svg" alt="A single Codec sits in the centre. Its decode side lands on a Read type with every column populated, including id. Its encode side comes from a Write type with the id column missing, which the database fills. Marked as future work.">
  <figcaption>The opaleye shape, not yet built: <code>dimap</code> lets one codec decode into a full <code>Read</code> type and encode from a <code>Write</code> type that has no <code>id</code> yet.</figcaption>
</figure>

The deeper reason to want a profunctor is that the type you decode into and the type you encode from need not be the same. opaleye leans on this: the write side omits the columns the database fills, so a fresh row has no `id` and Postgres supplies it, while the read side comes back with every column populated. `dimap` is what lets one codec land on a `Read` type on the way out and start from a `Write` type on the way in, one type on each side of the same description.

In the code today, `RowDecoder` is decode-only and encoding sits on a separate path, so the two-type opaleye shape above is desired work rather than shipping detail. The serial-primary-key marker from part 2 is the seam where it will go in, because the write side is exactly where "no `id` yet" needs to be expressible. The decision for now is to own the applicative `RowDecoder` and the profunctor `Codec` outright, taking the ideas from beam without taking its code. You maintain that machinery yourself; in return you get arity with no ceiling and one source of truth per column.

You can now move a `User` to a row and back from one. What you cannot yet do is decide when to write it, or even notice that you changed it: something has to watch the value, see that it differs from what the database holds, and act. In Haskell that watcher cannot see your change at all, which is the knot waiting on the other side.

---

{% include series-nav.html %}
