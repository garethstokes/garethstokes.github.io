---
layout: post
title: "the session that can't see your edit"
author: Gareth Stokes
permalink: /manifest/the-ordeal/
series: manifest
part: 4
of: 6
---

{% include series-nav.html %}

<figure>
  <img src="/assets/images/hero-mutate-vs-handback.svg" alt="In another language the session keeps watching one mutable object that is edited in place; in Haskell the edit produces a new value u-prime, leaving u untouched, and save hands the new value back to the session, so identity is carried by the primary key.">
  <figcaption>No hidden state to watch, so identity is the primary key: you hand the new value back with <code>save</code>.</figcaption>
</figure>

The trick that made SQLAlchemy famous is that you load a row, edit the object in front of
you, and at commit the session emits an UPDATE for exactly the columns you touched and no
others. Change the name and the email stays out of the statement. That convenience is not
free of assumptions. It needs mutation: the session holds the very object you are editing
and watches it change under your hands. Take that away and the whole mechanism has nothing
to watch.

Haskell takes it away. Write `let u' = u { userName = "Bob" }` and you have not edited
anything; you have built a second `User`, a new value standing next to the old one, while
`u` sits there exactly as it was. The session handed you `u` and now holds a thing nobody
will ever change again. `u'` lives in your hands, off to one side, invisible to the session
that loaded it. This is why Haskell went so long without a session layer in the
SQLAlchemy mould. The one move the design rests on cannot be made.

So drop the requirement that the session watch the value, and ask what an immutable `User`
still carries that the session can use. It carries its primary key, and the key is the
row's identity: `u` and `u'` are the same row precisely because they share `Key 42`. The
session does not need a live handle on a cell. It needs the value back, and a memory of
what the value looked like when it was loaded. You hand `u'` to `save`; the session finds
the baseline snapshot it kept when it read the row, sets the two side by side, and walks
them field by field, keeping the columns that differ and dropping the ones that match. That
walk is a generic fold over the record's columns. The current implementation encodes each
value to a vector of columns and compares the two vectors position by position, so what falls
out is a derived column-vector diff, nothing more exotic than that.

Sequencing all of this needs a particular kind of context, and it sits at the top of a
short ladder you have already started climbing. A functor lets you map a function over a
structure. An applicative lets you combine effects that do not depend on each other. A
monad lets you sequence steps where each one can use the result of the step before it, which
is exactly what `get` then `save` then commit demands. Manifest's `Db` is that monad, built
as a reader over a session in `IO`:

```haskell
newtype Db a = Db (ReaderT Session IO a)
  deriving (Functor, Applicative, Monad, MonadIO)

withSession     :: Pool -> Db a -> IO a
withTransaction :: Db a -> Db a
```

Every action in `Db` can reach the session through the reader and run real I/O, in order.
That is enough to make the snapshot bookkeeping disappear into ordinary-looking code. You
open a session over a pool, wrap the work in a transaction, and inside it the reads and
writes read like reads and writes:

```haskell
withSession pool $ withTransaction $ do
  mu <- get @User (Key 42)        -- baseline snapshot, when present
  for_ mu $ \u ->
    save u { userName = "Bob" }   -- stash; diff deferred
  -- commit -> flush emits:
  --   UPDATE users SET name = $1 WHERE id = 42
```

The `get` records what the row looked like the moment it loaded. The `save` does almost
nothing: it queues the value you handed back and returns, leaving the real work for later. At
commit the flush takes the queue and runs each save in turn, diffing the value against that
row's baseline snapshot and emitting an UPDATE that carries only the columns that changed. The
queue is a list of operations rather than a set of dirty keys, so two saves of the same row
before a flush simply run as two; a save whose value matches its snapshot diffs to nothing and
emits nothing at all.

<figure>
  <img src="/assets/images/fig-snapshot-diff-fold.svg" alt="The flush walks the baseline snapshot and the handed-back value field by field; id and email match, only the name cell differs, so the fold emits an UPDATE setting just the name column where id equals 42.">
  <figcaption>The flush folds the snapshot against the saved value column by column, keeping only what changed.</figcaption>
</figure>

The cost is real and worth naming. The session cannot see your edit, so you have to hand the
value back; forget the `save` and nothing happens, which is either a footgun or a feature
depending on your mood. In exchange `save` stays cheap, and the diff waits until flush,
where it runs once over the whole batch of dirty rows. When you want to write without any of
this (a blind update, a bulk delete across thousands of rows you never loaded) there is an
explicit-command path, `update key [...]` and `deleteWhere [...]`, that skips the snapshot
and goes straight to SQL. The default tracks; the escape hatch obeys.

The value is tracked now, and a save writes the smallest UPDATE that tells the truth. But a
`User` is more than its own columns. It has posts, and the posts are not fields on the
record; they are rows in another table that happen to point back at `Key 42`. Read
`user.posts` when you never loaded them and an empty list would be a lie, indistinguishable
from a user who has written nothing.

---

{% include series-nav.html %}
