---
layout: post
title: "a record that's three things at once"
author: Gareth Stokes
permalink: /manifest/the-call/
series: manifest
part: 1
of: 6
---

{% include series-nav.html %}

<figure>
  <img src="/assets/images/hero-one-record-three-faces.svg" alt="A single box labelled UserT f fans out to three faces: column metadata for building the table, a plain value for moving rows in and out, and a column reference for running a query. Choosing f picks the face.">
  <figcaption>One declaration, read three ways: the functor f picks the face.</figcaption>
</figure>

A table description has three jobs, and they pull in different directions:

1. Build the table. A migration needs the column names, their SQL types, which column is
   the primary key, which ones may be null.
2. Move rows in and out. A result row is decoded into an ordinary value, with `userName`
   handed to you as a `Text`; the same `Text` is encoded back as a column value when you
   insert or update.
3. Query. To filter on the name, `userName` has to be a typed reference to a column, an
   `Expr Text` carrying its type, that the builder can render as `users.name = $1`.

One table, three jobs. The opportunity here is to write the table out once, not three
times, and make each artifact a function of that single source — `schemaOf D`, `codecOf D`,
`queryOf D`. That is all
it means when we write `f(g(x))`: a single value with functions applied to it, a value
going in one end and transformations carrying it through. Define
`D` once; derive the rest.

The trouble is the input. Declare `D` as a plain record and you have already lost:

```haskell
data User = User
  { userId    :: Int
  , userName  :: Text
  , userEmail :: Maybe Text
  }
```

`schemaOf` and `codecOf` can both work from this, and manifest does derive them
generically. But `queryOf` is stuck. For a query `userName` has to be a column reference
that carries its type, an `Expr Text`, not a bare `Text`; and `schemaOf` needs to know
`userId` is a serial primary key, which the plain `Int` threw away the moment the record
was written. A function takes the value it is handed. It cannot reach back and change what
type each field is.

A dynamic language hides this behind a mutable model class at runtime; Haskell has no such
escape, so the openness has to live in the type itself.

So `f(g(x))` is the right shape with one piece missing: the input cannot be a finished
value. Each field has to stay open, free to be read as a runtime type for one job, a column
expression for another, a parcel of metadata for a third. The description needs a hole where
each field's interpretation will go.

That hole is a functor, which is a smaller idea.

A type is a set of values. `Bool` is the set `{True, False}`; `Int` is a larger but
unremarkable set, the whole numbers a machine word can hold. A function
`A -> B` sends each value of one set to a value of another.

A functor is one step past that. Some types are containers: `[a]` holds many values of
type `a`, `Maybe a` holds an optional one. If you have written `List<T>` or `Optional<T>`
in another language, these are the same idea: a type parameterised by the type it holds. For a container you can take an ordinary function `a -> b`
and run it inside, turning `[a]` into `[b]` or `Maybe a` into `Maybe b` without disturbing
the shape around it. That operation is `fmap`, and a container that supports it lawfully is
a functor.

Two laws make "lawfully" precise, and both come down to the same promise: mapping touches
the contents and never the shape. The first is identity, `fmap id = id`: map the function
that does nothing and nothing happens, so the list keeps its length and the `Maybe` stays
`Just` or `Nothing`. The second is composition, `fmap f . fmap g = fmap (f . g)`: mapping
`g` and then `f` is the same as mapping their composition in one pass, so no structure can
shift between the two steps. Mapping over a list is the first example everyone meets, and
it obeys both.

Notice what holds still there and what moves. In `Maybe a` the contents `a` vary while the
`Maybe` wrapper stays fixed. Manifest's central move is to invert that: hold the contents
fixed and let the wrapper vary, by making it a parameter of the record.

```haskell
data UserT f = User
  { userId    :: Field f (Pk Int)
  , userName  :: Field f Text
  , userEmail :: Field f (Nullable Text)
  }
  deriving (Generic)
```

`UserT` takes `f`, a type constructor rather than a type: a function from types to types,
the same sort of thing `Maybe` and `[]` are. That is what "higher-kinded" names, a
parameter one level up, a wrapper where you would normally expect a value. With `f` left
abstract, `Field f a` resolves to a different type for each choice of `f`.

In general the wrapper can be any functor at all, which is the full reach of higher-kinded
data. Conceptually `UserT Maybe` would be a user with every field optional, a patch, and
`UserT []` a column of values per field. manifest does not go that far: its `Field` is a
closed type family with only the readings the library actually needs, which the next parts
fill in. The shape is general; the use manifest makes of it is deliberately narrow.

<figure>
  <img src="/assets/images/fig-functor-distributes.svg" alt="In general higher-kinded data, Maybe User wraps the whole record while UserT Maybe pushes Maybe into every field; likewise a list of User versus UserT of list.">
  <figcaption>In general, f can be any functor — around the whole record, or pushed into every field. manifest's own <code>Field</code> is closed to just the readings it needs.</figcaption>
</figure>

That single declaration is what the whole library reads. Set `f` one way and it is the plain
value you decode a row into; set it another and it is the column metadata the schema is built
from; and from that same metadata the query layer takes the typed column references you filter
on. So the `schemaOf`, `codecOf`, and `queryOf` you sketched at the start are not three
hand-kept descriptions but one declaration read more than one way. Which readings those are,
and how each is built, is what the rest of the series works through, the value first.

This is Higher-Kinded Data, and adopting it is the first load-bearing decision in the
design. It earns the property the naive encodings could not: the three readings cannot
drift, because there is exactly one declaration and the compiler produces the rest from it.

This shape is not unique to manifest. [`barbies`](https://github.com/jcpetruzza/barbies) is a
delightful library built for exactly this style of programming, a whole toolkit for records
parameterised by a functor. Its plain shape wraps every field in the functor, `name :: f
String`, and the wrapper tends to stick around: even when you want the bare value, the fields
stay inside `f`, so you are forever putting values in to store them and pulling them back out
to read them. Manifest takes a different road. `Field f a` is a type family rather than a
plain wrapping, so for the value reading it erases `f` and leaves the bare type, an `Int` or a
`Text` with nothing to unwrap.

None of this is free. Every signature that touches a table now carries an `f`; type errors
mention `Field` before they mention `Int` or `Text`; and anyone reading the code has to learn
to look past the parameter to the record underneath. The design calls this the
type-complexity tax and pays it on purpose, betting that one source of truth is worth more
than three convenient copies that fall out of step. The rest of the series is, in part, a
test of whether that bet holds.

Even with the functor gone, you are only halfway to a plain `Int`. `userId` is `Field f (Pk
Int)`, where `Pk Int` is a marker standing for a serial primary key, so reaching a plain
`Int` means shedding the marker as well as the `f`. How that happens is where the next part
begins.

---

{% include series-nav.html %}
