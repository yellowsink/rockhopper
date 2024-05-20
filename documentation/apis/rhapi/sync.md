# `rockhopper.rhapi.syncf` and `synct`

These modules contain synchronization tools to help coordinate your fibers, and to provide thread sync tools that also
respect fibers.

If you are using multiple threads in your application, you should absolutely be using the `synct` tools for syncing,
as using the `core.sync` module may lead to unnecessary blocking and thus loss of performance
(["Don't block the executor"](https://fasterthanli.me/articles/pin-and-suffering])), or even deadlocking.

For single threaded scenarios, the `syncf` tools provide familiar looking APIs for keeping fibers in check that are
very efficient.
They should be familiar to developers coming both from traditional thread syncing (mutexes, events, etc),
and languages like Go (wait groups, message boxes ~= channels).

`synct` classes are safe to make `shared` (in fact, they *should* be `shared` as a rule)
and all methods will synchronously use locks to ensure thread safety
(which is non-ideal, but not a huge deal in this case).
They are carefully written to stay in locked sections as briefly as possible, and to avoid potential deadlocks.

## Note on `syncf` structs

The fiber syncing structs are stack allocated for efficiency, but this has a drawback. Value semantics.
If you try to pass one of these around, you make copies of it, and they become independent and break.

To prevent this, they have the copy constructors disabled, so that copying them is a compile error.

The solutions I can recommend to get around this are:
 - If you need to pass to a function, use the `ref` typeclass.
 - If you need the sync primitive somewhere else, and won't need the original copy any longer, you can safely use
   [`core.lifetime : move` and `moveEmplace`](https://dlang.org/phobos/core_lifetime.html#.move).
 - Take a pointer to the struct, and refer to it via that at all times:
   * If your code all happens within the current scope and the reference cannot escape, you can just `&` on a local var.
	* Use the `new` keyword (other memory allocation tools are available) to create one on the heap.

This does not matter for `synct` tools, as they are classes with reference semantics by default.

## `FEvent`

```d
struct FEvent
{
	bool isSignaled();
	void notify();
	void reset();
	void wait(); [ASYNC]
	bool wait(Duration); [ASYNC]
}
```

Waiting on an event will cause all waiting fibers to be suspended until it is notified.
Once it has been notified, waits on it will instantly resolve until it is reset.

You may pass a duration to wait for either the event or for a timeout, which will return true if the event was raised,
or false if it returned due to timeout.

## `FSemaphore`

```d
struct FSemaphore
{
	void notify();
	bool tryWait();
	void wait(); [ASYNC]
	bool wait(Duration); [ASYNC]
}
```

A semaphore works almost akin to a queue - fibers waiting on it are suspended until it is notified, and once notified
the next wait will resolve instantly, however *every notify will resolve exactly one wait*.

If you `notify` the semaphore, and three fibers are `wait`ing, only one will be released.

Similarly, if you notify 5 times on a semaphore, the next 5 waits will resolve instantly, and the 6th will then pause.

## `FMutex`

```d
struct FMutex
{
	void lock(); [ASYNC]
	void unlock();
}
```

This is a *recursive* (re-entrant) mutex. It is either locked or unlocked, and when a fiber `lock`s it, any other fibers
trying to lock it will be suspended until the locking fiber `unlock`s it.

Being recursive, the same fiber can lock it *multiple times*, and must unlock it the corresponding number of times to
actually release the lock. This is useful because a function can lock at the start and unlock before return and still
call itself, without unlocking earlier than is intended or breaking the mutex.

Only the current lock holder is allowed to unlock.

## `FRWMutex`

```d
struct FRWMutex
{
	void lockWrite(); [ASYNC]
	void lockRead(); [ASYNC]
	void unlockWrite();
	void unlockRead();
}
```

A read-write-mutex has two kinds of lock state: locked for reading, and locked for writing.

The mutex is NOT recursive.
It can have any number of read locks, but this means the write MUST be unlocked.
It can instead have ONE write lock, but this means there MUST be zero read locks.

This does not enforce immutability when read locked as it does not encapsulate any data, but can be used to enforce a
"many read, one write" lock mechanism as long as all usages act in good faith (which they should, as if you've got
issues with that, it's because you've chosen to disobey the lock in your own code.)

## `FGuardedResult(T)`

```d
struct FGuardedResult(T)
{
	bool hasValue();
	void set(T val);
	void nullify();
	T get(); [ASYNC]
	Nullable!T tryGet();
}
```

This is effectively a combination of an event and a local variable - when attempting to get a value when it has yet to
be set, the fiber will wait for it to be set by another.

## `FWaitGroup`

```d
struct FWaitGroup
{
	void add(uint);
	void done();
	void wait(); [ASYNC]
}
```

Wait groups are useful for parallel processing - add the number of fibers you're running, have each one call `done` once
it's finished, then `wait` for them all to finish.
This should be familiar to Go programmers.

## `FMessageBox(T)`

```d
struct FMessageBox(T)
{
	void send(T val); [ASYNC]
	void send(T val, false);
	T receive(); [ASYNC]
	Nullable!T tryReceive();
}
```

A message box contains a list of values, which allow sending messages between fibers asynchronously.
It works like channels in Go.

## `fSynchronized(alias F)`

```d
ReturnType!F fSynchronized(alias F)(Parameters!F) [ASYNC]
```

`fSynchronized` can be used similarly to the D `synchronized` attribute. Only one fiber is allowed to call the function
at once per instance of the template.

Be careful with this! You can safely instantiate this template on a named function and have it be the same everywhere,
but using this on a lambda is basically pointless.

This is equivalent to wrapping the call in an FMutex.

## `TEvent`

```d
class TEvent
{
	void notify();
	void reset();
	void wait(); [ASYNC]
}
```

`TEvent` works effectively the same as an `FMutex` except that it works across multiple threads.
You can create a `TEvent` on one thread, then notify it later while another thread's reactor has a fiber waiting on it.

It is the most basic primitive to sync up fibers across multiple threads.

## `TSemaphore`

```d
class TSemaphore
{
	void notify();
	bool tryWait();
	void wait(); [ASYNC]
}
```

`TSemaphore` works like a semaphore, but it works across threads as well as working across fibers.
