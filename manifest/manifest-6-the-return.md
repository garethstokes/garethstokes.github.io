---
layout: post
title: "the working, complete"
author: Gareth Stokes
permalink: /the-math-under-manifest/the-return/
series: manifest
part: 6
of: 6
---

{% include series-nav.html %}

<figure>
  <img src="/assets/images/hero-one-declaration-derives-all.svg" alt="A single box labelled UserT f passes through a deriving Generic step and fans out to four things GHC produces from it: the schema, the codec, the CRUD surface, and the relationship metadata. One declaration produces everything.">
  <figcaption>One declaration, through <code>deriving (Generic)</code>: the schema, the codec, the CRUD surface, and the relationships all fall out of it.</figcaption>
</figure>

The signature that looked like noise on the very first line reads plainly now. `Field f (Pk Int)` is a field whose interpretation waits on `f`; `Ent (Insert name l)` is a row you are building that the types know is mid-construction. Nothing in either was decoration. Learning to read them was the whole point of the walk, and the walk is over, so they are just types.

What stays with you is smaller than any one of those, and it answers a question that hung over the start. Nobody had built a SQLAlchemy-style Unit-of-Work for Haskell, and the reason was never that nobody wanted one. The obvious design wants a session that watches your objects and flushes their changes, and watching changes means mutating the objects it watches. Haskell will not mutate. That looks like a wall, and for a long time it read as one.

It was the opposite. Immutability did not block the design; it ruled out the cheap version and left only an honest one, where every decision had to be paid for in the types instead of hidden behind a mutable cell. Each piece of category theory in the series was the smallest tool that kept one of those decisions honest. A functor parameter so a single record declaration is table, value, and query at once. The identity functor so the value comes back bare, with the markers shed rather than wrapped. An applicative-and-profunctor codec so the round trip has one source of truth and no ceiling on the number of fields. A monad and a snapshot-diff fold so a value can be tracked without being touched. Type families so a relation you forgot to load is a compile error rather than a silently empty list. Walk any of them back and you reach the same root: you could not reach into a value and change it, so you taught the types to keep the books instead.

One light touch ties the whole stack to that first declaration. `deriving (Generic)` asks GHC to expose the record as a sum-of-products, and the shape it hands back, `Rep`, is itself one last functor over the field types.

```haskell
data UserT f = User
  { userId    :: Field f (Pk Int)
  , userName  :: Field f Text
  , userEmail :: Field f (Nullable Text)
  }
  deriving (Generic)

type User = UserT Identity
deriving via (Table "users" UserT) instance Entity User
```

From that derived view alone, manifest reads off the table metadata (names, SQL types, the primary key), the row codec, the `get`/`add`/`save`/`delete` defaults, and the typed column labels like `#userName` you filter on. You wrote the record once, and the schema, the codec, the CRUD, and the field labels are all that record, read at different angles by the compiler. Relations are the one thing you still spell out, in a `HasRelation` instance declared beside the entity; everything else is derived.

<figure>
  <img src="/assets/images/fig-the-ladder.svg" alt="A stack of six rungs, each derived from the one below it. The base rung is the single declaration UserT f. Above it: the functor parameter, the bare value, the codec, the tracked value, and the typed relations at the top. Each rung rests on the one beneath.">
  <figcaption>The series as a stack: each rung is derived from the one beneath it, and the whole of it stands on the single declaration at the base.</figcaption>
</figure>

The earlier parts each settled one rung, and from a distance you can see they were never separate ideas. They are one declaration, read more and more sharply, until the types carry the bookkeeping the mutation can't. Writing the working down before the code is what held the abstractions honest the whole way up. That a language which refuses to mutate forced the cleaner design, rather than forbidding the design at all, is the part worth keeping.

---

{% include series-nav.html %}
