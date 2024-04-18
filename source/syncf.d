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
// this is a recursive mutex - the SAME FIBER ONLY can call lock() multiple timse without deadlocking
// two fibers however still cannot hold a lock at once.
struct FMutex
{
	@disable this(ref FMutex); // see FEvent::this(ref FEvent)

	Fiber lockHolder; // null-safety: will be null iff lockcount == 0.

	uint lockcount;
	void lock()
	{
		auto thisF = Fiber.getThis;

		if (lockcount && lockHolder == thisF)
		{
			// recursive - increment lock
			lockcount++;
			return;
		}

		while (lockcount > 0) yield(); // wait for other fiber to unlock if necessary

		// initialize lock
		lockHolder = thisF;
		lockcount = 1;
	}
	void unlock()
	{
		lockcount--;
		if (lockcount == 0) lockHolder = null;
	}
}

// core.sync.rwmutex : ReadWriteMutex
struct FRWMutex
{

}
