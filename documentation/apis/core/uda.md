# `rockhopper.core.uda`

This module contains various UDAs (user-defined-attributes)
for communicating Rockhopper-specific information.

Each one will have an attribute e.g. `Foo`, which can be applied `@Foo`,
and a template `enum bool isFoo!()`.

Note that while enforcing the promises communicated by these UDAs is impossible,
the Rockhopper included APIs are guaranteed to correctly use them.

## `@Async` / `isAsync`

All functions marked `@Async` are declaring that they must be run from a fiber,
and may suspend your fiber if called.
This is always because they call some other `@Async` functions.

(The only async functions that are async for some reason other than calling
other async functions are calling secret internal reactor functions).

This is on the honours system and functions without `@Async` maybe async,
and it is impossible to enforce correct usage of this `@nogc` style nor
automatically applied, this would require compiler support.

## `@ThreadSafe` / `isThreadSafe`

When applied to a class, communicates that instances can safely be shared across threads.

When applied to a method, means that the function can be called from many threads.

E.G. `FEvent` only works if it is used on one thread, so it is not `@ThreadSafe`,
but an instance of `TEvent` is safe to use from many threads at once,
so it is `@ThreadSafe`, and `TEvent.wait()` can be called on that instance from any thread, so is `@ThreadSafe`.

All methods `@ThreadSafe` classes tend to be `@ThreadSafe`, though this isn't a hard rule.

## `@Synchronized` / `isSynchronized`

Methods that are `@Synchronized` act similarly to the built-in `synchronized` attribute - only one call to this function may be in flight at a time,
and any subsequent calls to the function will suspend your fiber
until the current call completes.
