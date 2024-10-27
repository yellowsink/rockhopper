// `synct` has synchronization primitives like `syncf` that are thread safe, and will lock between fibers across
// multiple threads' reactors.
// these should be preferred over core.sync as instead of e.g. one thread being allowed to lock a mutex, only one fiber
// is allowed to lock that mutex, across many threads.

module rockhopper.rhapi.synct;
import rockhopper.core.uda : Async, ThreadSafe;

import rockhopper.core.llevents : waitThreadEvent;
import core.atomic : atomicOp;

// for note for future me:
// `synchronized` methods lock on the whole instance, not per-method:
// https://dlang.org/spec/class.html#synchronized-methods #16.6.1

// These need to be classes so we can use `synchronized(this)` and `synchronized` members

final shared @ThreadSafe class TEvent
{
@ThreadSafe:

	import eventcore.core : eventDriver;
	import eventcore.driver : EventID, EventDriver;
	import std.typecons : Tuple, tuple;
	import core.thread.osthread : Thread;

	alias ThreadEventsTy = Tuple!(shared(EventDriver), EventID)[typeof(Thread.getThis.id)];

	private bool triggered;
	// you may only await an event from the thread that created it, so we need one event per thread
	private ThreadEventsTy threadEvents;

	synchronized void notify()
	{
		if (triggered)
			return; // i don't think this is necessary but can't hurt.

		triggered = true;

		foreach (_, tup; threadEvents)
			tup[0].events.trigger(tup[1], true);

		threadEvents = ThreadEventsTy.init;
	}

	synchronized void reset()
	{
		if (triggered)
		{
			triggered = false;
			threadEvents = ThreadEventsTy.init;
		}
		else
		{
			// resetting an event that has not been triggered is a no-op!
			// assert(0);
		}
	}

	void wait() @Async
	{
		auto tid = Thread.getThis.id;

		while (!triggered)
		{
			EventID ev = void; // always assigned

			synchronized (this)
			{
				// while in a synchronized, you can cast away a `shared`
				// -- technically you can cast shared away any time, but its safe here :)
				// use a pointer else this causes a copy and that screws stuff up.
				// we still have to make sure the contents of the AA are shared due to transititivy,
				// but this fixes it not liking us trying to do the assignment *at all*
				auto tEvs = cast(ThreadEventsTy*)&threadEvents;

				if (tid in *tEvs)
				{
					ev = (*tEvs)[tid][1];
				}
				else
				{
					ev = eventDriver.events.create();
					(*tEvs)[tid] = tuple(cast(shared) eventDriver, ev);
				}
			}

			waitThreadEvent(ev);
			// if the thread event resolves, triggered may still be false because another fiber got there before us,
			// and reset the event. to prevent this case, we loop around again.
		}
	}
}

final shared @ThreadSafe class TSemaphore
{
@ThreadSafe:

	// we always access this inside of a `synchronized` so atomics are unnecessary
	// __gshared disables the compiler enforcement for that
	// MAKE SURE YOU NEVER USE THIS OUTSIDE OF A `synchronized(this)` OR `synchronized` METHOD
	private __gshared uint count;
	private TEvent notifyEv = new TEvent;

	synchronized void notify()
	{
		count++;

		// notify this event when a new notify is sent
		// and reset it after each wait.
		notifyEv.notify();
	}

	synchronized bool tryWait()
	{
		if (count == 0)
			return false;

		count--;
		notifyEv.reset(); // in case nobody else is waiting, reset it ready for next time
		return true;
	}

	void wait() @Async
	{
		// check if we can go immediately
		synchronized (this)
		{
			if (count > 0)
			{
				notifyEv.reset(); // must have been triggered, likely not cleared up.

				count--;
				return;
			}
		}

		// no? okay, wait for the event, then see if we can decrement, if not try again.
		while (true)
		{
			notifyEv.wait();
			notifyEv.reset(); // reset the lock for next time. should be safe to do this lock-free.

			synchronized (this)
			{
				if (count > 0)
				{
					count--;
					return;
				}
			}
			// count was not greater than zero, so someone else got here first!
			// we let go of the lock and get back to waiting.
		}
	}
}

// non-recursive mutex
// im PRETTY SURE this is safe but don't shoot me if it isn't im doing my best
final shared @ThreadSafe class TMutex
{
@ThreadSafe:

	private bool locked;
	private TEvent unlockEv = new TEvent;

	void lock() @Async
	{
		while (true)
		{
			// get control of this and check if we can take it
			synchronized (this)
			{
				if (!locked)
				{
					// we can lock!
					locked = true;
					return;
				}
			}

			// we didn't get it this time, wait for the unlocker to notify us.
			// explanation to future me as to why this has to be done with a wait()-reset() like this:
			// immediately reset the event. this generally will cause the first fiber to be awoken to reset and try and lock,
			// and all further waiting fibers will not exit wait() as an immediate reset stops the wait from resolving.
			// !!! NOTE THIS PATTERN ONLY ALLOWS ONE FIBER TO BE WOKEN PER NOTIFY !!!
			unlockEv.wait();
			unlockEv.reset();
		}
	}

	synchronized void unlock()
	{
		assert(locked, "unlocking an unlocked TMutex makes no sense");
		locked = false;
		unlockEv.notify();
	}
}

// TODO: remutex
// TODO: rwmutex

// an equivalent of the `synchronized` attribute that also ensures mut-ex of fibers, not just threads.
template tSynchronized(alias func)
{
	import std.traits : isSomeFunction, ReturnType, Parameters;

	static assert(isSomeFunction!func, "tSynchronized may only be instantiated with a function");

	// even though this is always true, if we don't if for it, we get more compiler errors than just the assert
	// and nobody needs that, so just be satisfied with the assert.
	static if(isSomeFunction!func)
	{
		TMutex m;

		ReturnType!func tSynchronized(Parameters!func args) @Async
		{
			m.lock();
			func(args);
			m.unlock();
		}
	}
}

// a nullable in which trying to get the value while its null waits for a result to be set
final shared @ThreadSafe class TGuardedResult(T)
{
@ThreadSafe:
	import std.typecons : Nullable;

	private TEvent setEv = new TEvent;
	private bool hasValue;
	private T value;

	synchronized void set(T val)
	{
		value = T;
		hasValue = true;
		setEv.notify();
	}

	synchronized void nullify()
	{
		hasValue = false;
		value = T.init;
		// otherwise one fiber would loop in get() and cause issues.
		setEv.reset();
	}

	T get() @Async
	{
		while (true)
		{
			synchronized (this)
			{
				if (hasValue)
					return value;
			}

			setEv.wait();
			// we don't want to reset as the wait-reset pattern only wakes one fiber per notify
			//setEv.reset();
		}
	}

	synchronized Nullable!T tryGet()
	{
		if (hasValue) return value;
		return Nullable!T.init;
	}
}

// like a golang WaitGroup
// see FWaitGroup for more detailed notes on how this works and how it differs from a semaphore
final shared @ThreadSafe class TWaitGroup
{
@ThreadSafe:
	private TEvent doneEv = new TEvent;
	// safety: this is only accessed inside `synchronized` sections.
	private __gshared uint count;

	this() { }

	this(uint c)
	{
		count = c;
	}

	synchronized void add(uint amt)
	{
		count += amt;
		doneEv.reset();
	}

	synchronized void done()
	{
		assert(count > 0);
		count--;
		doneEv.notify();
	}

	void wait() @Async
	{
		while (true)
		{
			synchronized (this)
			{
				if (count == 0) return;
			}

			doneEv.wait();
			// see note in TGuardedResult(T).get()
			//doneEv.reset();
		}
	}
}

// kinda like a channel in go
final shared @ThreadSafe class TMessageBox(T)
{
@ThreadSafe:
	import std.container : DList;
	import std.typecons : Nullable;

	private TEvent sendEv = new TEvent;
	private DList!T queue;

	synchronized void send(T val, bool shouldYield = true) @Async
	{
		queue.insertBack(val);
		sendEv.notify();
		if (shouldYield) yield();
	}

	T receive() @Async
	{
		while (true)
		{
			synchronized (this)
			{
				if (!queue.empty)
				{
					auto f = queue.front;
					queue.removeFront();
					return f;
				}
			}

			// wait-reset is the right pattern here as we only really want one thread to wake per notify
			sendEv.wait();
			sentEv.reset();
		}
	}

	synchronized Nullable!T tryReceive()
	{
		if (queue.empty) return Nullable!T.init;
		// in a good display of why synct is less efficient than syncf,
		// FMessageBox just calls receive() here for free, but that causes an extra lock here :(
		auto f = queue.front;
		queue.removeFront();
		return f;
	}
}
