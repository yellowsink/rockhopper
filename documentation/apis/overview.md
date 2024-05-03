## Rockhopper API overview

Rockhopper has multiple different APIs which you can use to interact with it.
This is to match a wide range of needs and use cases.

Broadly, there are three primary sets of APIs. `core` (and within it, `llevents`), `rhapi`, and `std`.

`core` provides the lowest level tools to interact with Rockhopper.
Within it are tools for talking directly to the reactor, and all the other APIs can be built using a combination of
rockhopper core and [`eventcore`](https://github.com/vibe-d/eventcore/).

`rhapi` is the native API for writing programs with rockhopper.
It has high level, easy to use interfaces for asynchronous programming, with as much flexibility as is practical
exposed.

Finally, `std` contains APIs that essentially look exactly like the Phobos standard library APIs.
This is designed to make transition to Rockhopper (from e.g. threads) easier.

When individual functions are discussed in these docs, some may be marked with the following notes:
 - "async" - this function MUST be called from within a fiber, and MAY suspend it indefinitely.
 - "synchronized" - if one fiber is part way through executing this function, any others that call it will be suspended until it finishes. This only occurs with async.
 - "thread-safe" - you may call this function from another thread safely via a
   [`shared`](https://tour.dlang.org/tour/en/multithreading/synchronization-sharing) reference (only applicable to class/struct methods). Please see [Thread Safety](../threading.md) for more information.

The top level `rockhopper` package re-exports everything from `rockhopper.core.reactor`, for convenience.
