# Introduction to Rockhopper

## What is Rockhopper?

Rockhopper is a cross-platform library for writing asynchronous programs in D.
It is designed to be easy, flexible, and relatively performant.

It provides a scheduler ("reactor") which allows multiple concurrent pieces of code to run on a single thread,
and a rich set of APIs to perform asynchronous operations efficiently.

## Getting Started

To start, install the rockhopper package from dub:

```sh
dub add rockhopper
```

Then import the essentials and set up an async entrypoint:

```d
import rockhopper;

mixin rhMain!({
	// write your code here!
});
```

Now you can spawn concurrent fibers with `spawn`, and pass execution to other fibers with `yield`.

## Fiber Concurrency in a nutshell

Rockhopper's approach to concurrency is to use *fibers*.
A fiber is named after a thread, as it superficially acts similar to one, however it works very differently.

Threads truly run in parallel, and this leads to the need for complex synchronization primitives such as locks.
Fibers, by comparison, are effectively just functions that can be interrupted part-way-through and then resumed.
This can be used to build thread-like code that actually does not need any locks and runs entirely on one thread.

This simplifies your code, and can boost performance in some cases.

For example, when you sleep in a thread, everything on that thread pauses, and waits for the operating system to wake it
up. In practice, the OS can run other processes during this time, to make efficient use of the processor.

With fibers, you don't have to suspend execution at all - instead, another waiting fiber runs instead, and the runtime
simply ensures that your fiber is not called again until your sleep time runs out.
An efficient scheduler, like Rockhopper has, can then inform the OS of what you're waiting for only when appropriate
(e.g. all fibers are waiting for something).

### Tasks

A common approach to async abstraction is use of *tasks*.
Examples of this include .NET's `Task`, Javascript's `Promise`, and Rust's `Future`.

This is a nice abstraction because it gives an object you can pass around and use in synchronous contexts, and makes it
easier for the runtime to do "smart" scheduling onto thread pools and the like.

Rockhopper, however, generally does not follow the belief that tasks should be the *default*.
If you look at most code written using tasks, you generally end up calling some async function and then immediately
`await`ing it. This is unnecessary overhead in all of these cases,
so Rockhopper instead uses a more thread-like pattern.
If a function is async, it will just implicitly suspend your fiber as if it was a blocking function in a thread.

If you prefer programming with tasks, [we offer them optionally too](apis/rhapi/task.md).
Note that this does not allow you to use asynchronous functions without correctly using the rockhopper reactor.

## Why not vibe.d?

[vibe.d](https://vibed.org/) is a similar fiber runtime that already exists, so why does Rockhopper exist?

vibe is a much larger project, and is more a web framework than *just* an async runtime - it includes a web server,
logging, argument handling and other lifecycle things, a multi-threaded work stealing fiber scheduler, etc.

This is all just a *lot* for some applications, and Rockhopper aims to fill the needs of something small,
without adding tons of unnecessary features.

It's worth noting that without vibe, Rockhopper would likely not exist, due to our use of their excellent
[eventcore](https://github.com/vibe-d/eventcore/) library, which handles a lot of the really tricky parts for us.

## Why not `std.concurrency.FiberScheduler`?

In short: it doesn't provide any provision for I/O, what it *does* support (sleep only) is difficult to use,
and the scheduler busy-waits.

## Where to go next

<!-- TODO: You can find example code for various small applications in the examples folder of the source code. -->

- [The API references](apis/README.md) - Rockhopper has a few different APIs, and they are documented in depth.
  This also explains what you can do with Rockhopper and how.
- [Drawbacks](drawbacks.md) (and gotchas!) of using Rockhopper.
- [Threads and Thread-Safety](threading.md) - Rockhopper *can* work with multiple threads, but it involves more care.

