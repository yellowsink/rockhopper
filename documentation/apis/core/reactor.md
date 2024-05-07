# `rockhopper.core.reactor`

This module contains two kinds of APIs - fiber management APIs, and what are internal implementation details.

## `spawn`

```d
void spawn(void delegate() fn)
```

This is the function used to spawn new fibers. It will queue a fiber onto the current thread's reactor to be ran.

If you are already within a running entrypoint, it will be executed at some point in the future with no other necessary
work.
If called while the reactor is not running, you may need to use the `entrypoint` call to start it.

This call returns instantly.

## `entrypoint`

```d
void entrypoint(void delegate() fn)
void entrypoint(void function() fn)
```

At the root of your Rockhopper application, you have one fiber that everything else can run from.
This is done via `entrypoint`, which runs the passed callback in this thread's reactor. From within this callback you
can do things asynchronously and spawn more fibers.

This call will return once the reactor finishes (when all fibers terminate, or it is explicitly early-exited).

You may not call `entrypoint` if that thread already has a running reactor.

## `yield`

```d
void yield() [ASYNC]
```

Yielding from within your fiber will stop execution of it, passing it back to the reactor.
Generally this leads to one of two outcomes - other waiting fibers will be executed instead, or the reactor will wait
for a notification from the OS, suspending the thread.

You can expect your fiber to be called again later, and execution will resume after yield() returns.

A common pattern is to call yield in a loop until a condition is true, and this generally works quite well, but you
should be careful when doing this - only do it when waiting on something that ultimately depends on some kind of OS
event (think `llevents` apis and `rhapi` functions that are doing I/O etc), as if all of your fibers are all yield
looping, then the reactor will end up busy-waiting and your program will sit at 100% cpu use, which is obviously
non-ideal.

## `earlyExit`

```d
void earlyExit()
```

Early-exiting the reactor instantly stops it. IF called from within a fiber, your fiber will yield, and once control
passes to the reactor, no events will be waited for and no fibers will be executed. `entrypoint` will return.

## `llawait`

```d
SuspendReturn llawait(SuspendSend) [ASYNC]
```

This function is effectively there for `llevents` to talk to the reactor.
Given an object from `suspends`, this function will pause your fiber until it completes, then return the result.

This is the only way to correctly inform the reactor that you wish to pause your fiber for a resource,
and all Rockhopper APIs are built on it.

## `cloneRefAddress`

```d
RefAddress cloneRefAddress(scope RefAddress) nothrow @trusted
```

This is an internal utility that clones an eventcore `RefAddress` to the heap, as their APIs often return instances of
this type that depend on stack-allocated memory, preventing them from otherwise being escaped outside of that scope.
