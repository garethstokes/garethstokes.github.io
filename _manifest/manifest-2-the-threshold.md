---
layout: post
title: "making the markers disappear"
author: Gareth Stokes
permalink: /manifest/the-threshold/
series: manifest
part: 2
of: 6
---

{% include series-nav.html %}

<figure>
  <img src="/assets/images/hero-identity-erasure.svg" alt="The field type Field f of Pk Int branches at two gates. Through the Identity gate it emerges as a bare Int, the value you hold. Through the Exposed gate it keeps its PrimaryKey and Serial markers, which the schema deriver reads.">
  <figcaption>One gate erases the markers to a value; the other keeps them for the deriver. Same declaration, chosen by f.</figcaption>
</figure>

Part 1 left the record parameterised, and that parameter has a cost you feel at once. The
value you actually want to hold — a `User` you can pattern-match, print, pass around — is
buried. Write `UserT f` and `userId` has type `Field f (Pk Int)`, which expands to
`Field f (PrimaryKey (Serial Int))`: a functor you have not yet chosen, wrapped around a
marker that stands in for "primary key, serial." None of that is a number you can add to.

An ORM in another language would hand you a clean object and keep the schema details to one
side, in a decorator or a registry. We have no runtime side to keep them on and no
annotation syntax to strip them with. The markers live in the type, so the type is where
they have to come off.

The way off is the smallest functor there is. `Identity a` holds an `a` and does nothing
else; mapping a function over it just applies the function. In the language of part 1 it is
the do-nothing container, and to a category theorist it is the identity functor: the one
that composes with any other functor and leaves it unchanged. If any choice of `f` should
give you the plain value back, it is this one.

Choosing it does give you the plain value, though not the way `barbies` would. There a field
is `f a`, so `User Identity` would still leave you holding `Identity Int`, one wrapper to
peel. Manifest spends the choice differently. `Field` is a type family rather than plain
application: a function that runs in the compiler, taking types to types, that
pattern-matches on `f`:

```haskell
type family Field f a where
  Field Identity a = Base a       -- the value you hold
  Field Exposed  a = Exposed a    -- the metadata the deriver reads
```

The `Identity` case throws the wrapper away and hands the rest to `Base`, a second small
family whose only job is to strip the markers down to the runtime type:

```haskell
type family Base a where
  Base (PrimaryKey a) = Base a
  Base (Serial a)     = a
  Base a              = a
```

Run those and the noise unwinds a layer at a time:

<pre class="diagram">
  Pk Int  =  PrimaryKey (Serial Int)

  Field Identity (Pk Int)
    = Base (PrimaryKey (Serial Int))
    = Base (Serial Int)
    = Int                  (userId :: Int)

  Field Exposed (Pk Int)
    = Exposed (Pk Int)     (kept for the deriver)
</pre>

So `type User = UserT Identity` makes `userId :: Int`, on the nose. The `Pk Int` marker did
its job (it told the deriver this column is a serial primary key) and then vanished from the
value, with no annotation written anywhere, because it was a fact about the type and the
type is what got rewritten.

The second branch is the one that keeps them. `UserT Exposed` resolves every field
through `Field Exposed a = Exposed a`, so the markers stay on, and the code that generates
schema reads them straight off. One declaration, two readings: the value forgets the
markers, the schema remembers them.

This is where the `barbies` comparison flips. barbies needs a second type parameter to reach
a bare record, a `Wear`/`Bare`/`Covered` machine layered over `f`, because its `f a` can
only ever wrap. Manifest reaches bare with one parameter by making `Field` a family and
letting `Identity` be the branch that erases. The price shows up the other way round:
`Field f (Pk Int)` reads heavier than `f a`, and you cannot tell at a glance that it is an
`Int` without knowing the family. barbies has the cleaner field type; manifest has the
cleaner record, and the markers besides. (barbies would never have carried the markers in
the first place, since it has no reason to read database meaning out of a field.)

<figure>
  <img src="/assets/images/fig-barbies-vs-manifest.svg" alt="barbies' Person takes two parameters, a Wear knob for bare-or-covered and the functor f. Manifest's UserT takes one parameter, f, because the Field type family handles erasure.">
  <figcaption>Same bare value, fewer knobs: manifest folds bare-versus-covered into the <code>Field</code> family, so one parameter does what barbies needs two for.</figcaption>
</figure>

So the record now reads two ways from one declaration: a clean value under `Identity`, a
bag of schema facts under `Exposed`, written once. What it still cannot do is talk to the
database. Postgres deals in columns and bytes, not `User` values, so what comes next is the
round trip in both directions: a row decoded into a value, and a value encoded back into a
row, for as many fields as the record has and with no ceiling on the count.

---

{% include series-nav.html %}
