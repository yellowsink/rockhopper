// `syncf` contains fiber synchronization primitives. They provide familiar looking sync tools with no thread safety.

module syncf;

import reactor : yield, spawn;
import llevents : sleep;
import std.datetime : Duration;
import std.typecons : Nullable;
import core.thread.fiber : Fiber;

// core.sync.event : Event
struct FEvent
{
	// this does not have reference semantics so purposefully prevent footgunning, use a FEvent* if you need it.
	@disable this(ref FEvent);

	bool isSignaled;

	void set() { isSignaled = true; }
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
