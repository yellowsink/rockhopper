# `rockhopper.core.threading`

This module contains thread primitives that are useful for working with threads in your Rockhopper program.
Also see [Threading](../../threading.md).

You should prefer these over `core.thread.osthread.Thread`.

## `ThreadHandle`

```d
struct ThreadHandle
{
	Thread th;
	shared(EventDriver) ed;

	void join(); [ASYNC]
	void spawn(void delegate());
}
```

`ThreadHandle` wraps an instance of a `Thread` to also have a copy of the relevant event driver, to enable asynchronous
interaction with that thread.

Calling `join` is equivalent to calling `joinThread` on this handle's `Thread`,
and calling `spawn` is equivalent to calling `spawnInThread` on this handle's `EventDriver`.

## `spawnThread`

```d
ThreadHandle spawnThread(void delegate() fn);
```

Spawns a thread, and runs the given function as a fiber in that thread's reactor.
The thread will finish when the reactor exits.

This allows you to spawn a fiber and immediately use asynchronous calls within it.
It also retrieves the event driver for you.

## `spawnInThread`

```d
void spawnInThread(shared(EventDriver), void delegate());
```

Given another thread's event driver, spawns a fiber on that thread's reactor.
You may only call this given that the reactor on the target thread is still running.

## `joinThread`

```d
void joinThread(Thread th); [ASYNC]
```

Asynchronously waits for this thread to exit from within any fiber.
If you call this on yourself, you will deadlock your thread and by extension application.
