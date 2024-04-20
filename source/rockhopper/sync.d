// `sync` contains fiber synchronization primitives.
// They provide familiar looking sync tools with support for fibers, ~~with optional thread safety~~.

// when thread safety is off, they are designed to be as low overhead and efficient as possible.
//   (stack allocated structs without locks, etc)
// ~~when on, they can be shared across many threads' reactors. This has performance and DX side effects.~~

module rockhopper.sync;

import rockhopper.core.reactor : yield, spawn;
import rockhopper.core.llevents : sleep, waitThreadEvent;
import std.datetime : Duration;
import core.thread.fiber : Fiber;
import core.atomic : atomicOp;

// core.sync.event : Event
struct FEvent
{
	// this does not have reference semantics so purposefully prevent footgunning, use a FEvent* if you need it.
	@disable this(ref FEvent);

	bool isSignaled;

	void notify() { isSignaled = true; }
	void reset() { isSignaled = false; }

	void wait()
	{
		while (!isSignaled) yield();
	}

	bool wait(Duration timeout)
	{
		bool timedOut;
		spawn({
			sleep(timeout);
			timedOut = true;
		});

		while (!isSignaled && !timedOut) yield();
		return isSignaled;
	}
}

/+shared class TEvent
{
	import eventcore.core : eventDriver;
	import eventcore.driver : EventID, EventDriver;

	shared EventID ev;
	shared bool triggered;
	// storing a shared(EventDriver) lets us notify() from other threads
	shared EventDriver sourceDriver;
	this()
	{
		// i'm pretty sure two threads can't construct the *same* class at once so i won't `synchronized` here
		// you'd have to share a pointer and have two threads try to emplace it at once (?)

		sourceDriver = cast(shared) eventDriver;
		ev = eventDriver.events.create();
	}

	import std.stdio;

	synchronized void notify()
	{
		triggered = true;
		sourceDriver.events.trigger(ev, true);
	}

	synchronized void reset()
	{
		if (triggered)
		{
			sourceDriver = cast(shared) eventDriver; // we're the new source!
			ev = eventDriver.events.create();
			triggered = false;
		}
		else
		{
			// resetting an event that has not been triggered is a no-op!
		}
	}

	void wait()
	{
		if (triggered) return;
		waitThreadEvent(ev);

		assert(triggered, "if the thread event resolves, triggered should be true!");
	}
}+/

// this is like an FEvent however instead of just wrapping a bool, it keeps a count,
// such that exactly as many wait()s are resolved as notify()s are called.
// one notify resolves one wait.
// core.sync.semaphore : Semaphore
struct FSemaphore
{
	@disable this(ref FSemaphore); // see FEvent::this(ref FEvent)

	uint count;

	void notify() { count++; }

	bool tryWait()
	{
		if (count == 0) return false;
		count--;
		return true;
	}

	void wait()
	{
		while (count == 0) yield();
		count--;
	}

	bool wait(Duration timeout)
	{
		bool timedOut;
		spawn({
			sleep(timeout);
			timedOut = true;
		});

		while ((count == 0) && !timedOut) yield();
		if (count == 0) return false;

		count--;
		return true;
	}
}

// thread safe FSemaphore
// TODO: work in progress, untested and probably not correct
/+class TSemaphore
{
	shared uint count;

	void notify()
	{
		atomicOp!"+="(count, 1);
	}

	synchronized bool tryWait()
	{
		if (count == 0)
			return false;
		atomicOp!"-="(count, 1);
		return true;
	}

	void wait()
	{
		while(1)
		{
			auto done = false;
			synchronized(this)
			{
				if (count > 0)
				{
					atomicOp!"+="(count, 1);
					done = true;
				}
			}

			if (done) break;
			yield();
		}
	}

	bool wait(Duration timeout)
	{
		bool timedOut;
		spawn({
			sleep(timeout);
			timedOut = true;
		});

		while (!timedOut)
		{
			auto done = false;
			synchronized (this)
			{
				if (count > 0)
				{
					atomicOp!"+="(count, 1);
					done = true;
				}
			}

			if (done)
				break;
			yield();
		}

		return !timedOut;
	}
}+/

// core.sync.mutex : Mutex
// this is a recursive mutex - the SAME FIBER ONLY can call lock() multiple times without deadlocking
// two fibers however still cannot hold a lock at once.
struct FMutex
{
	@disable this(ref FMutex); // see FEvent::this(ref FEvent)

	Fiber lockHolder; // null-safety: will be null iff lockcount == 0.

	uint lockcount;
	void lock()
	{
		auto thisF = Fiber.getThis;

		if (lockHolder == thisF)
		{
			assert(lockcount > 0, "when there is a lockholder, there must be a lock");
			// recursive - increment lock
			lockcount++;
			return;
		}

		while (lockcount > 0) yield(); // wait for other fiber to unlock if necessary

		assert(lockHolder is null, "when theres no locks, there can't be a holder of locks");

		// initialize lock
		lockHolder = thisF;
		lockcount = 1;
	}
	void unlock()
	{
		// TODO: should we assert(lockHolder == Fiber.getThis)? or do we allow unlocking from other fibers?
		assert(lockHolder !is null);
		assert(lockcount > 0);
		lockcount--;
		if (lockcount == 0) lockHolder = null;
	}
}

// core.sync.rwmutex : ReadWriteMutex
// not re-entrant.
// a mutex that can either be locked for reading or writing.
// many read locks are allowed at once and zero write locks OR exactly one write lock and zero read locks
// TODO: consider if this SHOULD be re-entrant in future. the reasons for not doing this in core may not apply here!
// TODO: i have not tested this yet!
struct FRWMutex
{
	@disable this(ref FRWMutex); // see FEvent::this(ref FEvent)

	bool writeLocked;
	uint readLocks; // writeLocked => readLocks = 0 (in the mathematical sense of =>)

	void lockWrite()
	{
		// note that after waiting for all read locks to be freed, a write lock may have been placed again!
		// (or vice versa) so we must write to ensure no locks AT ALL before locking

		if (writeLocked)
			assert(readLocks == 0, "cannot be any read locks while a write lock is held");

		// wait for all locks of any kind to be freed
		while (writeLocked || readLocks > 0) yield();

		writeLocked = true;
	}

	void lockRead()
	{
		if (writeLocked)
		{
			assert(readLocks == 0, "cannot be any read locks while a write lock is held");

			// its okay if someone else gets a read lock while we're yielding
			while (writeLocked) yield();
		}

		readLocks++;
	}

	void unlockWrite()
	{
		assert(writeLocked);
		assert(readLocks == 0);

		writeLocked = false;
	}

	void unlockRead()
	{
		assert(!writeLocked);
		assert(readLocks > 0);

		readLocks--;
	}
}

// a lighter-weight thread-unsafe fiber equivalent of the dlang built in `synchronized` attr
// only one fiber can be in the process of executing this function at once.
template fSynchronized(alias func)
{
	import std.traits : isSomeFunction, ReturnType, Parameters;

	static assert(isSomeFunction!func, "FSynchronized may only be instantiated with a function");

	// even though this is always true, if we don't if for it, we get more compiler errors than just the assert
	// and nobody needs that, so just be satisfied with the assert.
	static if(isSomeFunction!func)
	{
		FMutex m;

		ReturnType!func fSynchronized(Parameters!func args)
		{
			m.lock();
			func(args);
			m.unlock();
		}
	}
} // i learned templates from scratch for this, and i'm proud of the result :) -- sink

// like std typecons Nullable!T but calling .get waits for a value
// TODO: there has to be a better name for this surely
struct FGuardedResult(T)
{
	@disable this(ref FGuardedResult); // see FEvent::this(ref FEvent)

	bool hasValue;
	T value;

	void set(T val)
	{
		value = val;
		hasValue = true;
	}

	void nullify() {
		hasValue = false;
		value = T.init;
	}

	T get()
	{
		while (!hasValue) yield();
		return value;
	}
}

// like a golang WaitGroup
// while a semaphore releases one wait per notify (many notify -> many wait),
// and an event releases all waits on one notify (one notify -> many wait),
// a waitgroup holds waits until a set quantity of notifies have happened (many notify -> one wait)
// tip: you can pass the initial amount of notifies required in the constructor instead of using add
struct FWaitGroup
{
	@disable this(ref FWaitGroup); // see FEvent::this(ref FEvent)

	uint count;

	void add(uint amt)
	{
		count += amt;
	}

	void done()
	{
		assert(count > 0);
		count--;
	}

	void wait()
	{
		while (count > 0) yield();
	}
}
