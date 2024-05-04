# Drawbacks of Rockhopper

There are a few reasons why Rockhopper may not be the best option for your application in particular.
This (obviously non-exhaustive) page goes over a few of those.

## Single-threaded reactor

The reactor implementation runs on only a single thread, by design.
This means that if you are, say, building a web server handling hundreds of thousands of requests on a 64-core server,
Rockhopper is going to waste 63/64ths of your potential processing power.

You can get around this by either spawning multiple threads with their own reactors, or by just using something designed
for it like vibe.

## Lack of cancellation

At present, Rockhopper does not include any cancellation mechanism, so if you wish to be able to interrupt something
partway-through, you're out of luck.

## Implicit yield

This is as much an upside as a downside. It is a conscious design choice that asynchronous functions implicitly yield
your fiber, as if you were blocking a thread, however this can be undesirable to some, who might prefer a more obvious
marker that they are causing their fiber to be suspended.

One option here is to make liberal use of tasks.

## `entrypoint`

You cannot simply open your project and start using fibers.
Technically Rockhopper could be modified to get around this, but for the time being it is most sensible to make starting
the reactor explicit.

This has some side effects if you have libraries that provide callbacks, that for example, the reactor may complete and
exit before you call spawn.

Generally, just try to make sure you don't let all your fibers die, then try to spawn a new one.

## Heap allocation

Rockhopper is not the most efficient possible implementation, and does make some performance sacrifices for comfort.
For example, some eventcore APIs return values to you that are only valid within the callback, due to referencing
stack-allocated memory.
Where appropriate, Rockhopper just clones this to the heap to remove the limitation.
