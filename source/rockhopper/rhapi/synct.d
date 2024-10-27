// `synct` has synchronization primitives like `syncf` that are thread safe, and will lock between fibers across
// multiple threads' reactors.
// these should be preferred over core.sync as instead of e.g. one thread being allowed to lock a mutex, only one fiber
// is allowed to lock that mutex, across many threads.

module rockhopper.rhapi.synct;
import rockhopper.core.uda : Async, ThreadSafe, Synchronized;

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

	// you may only await an event from the thread that created it, so we need one event per thread
	// SAFETY: only accessed within `synchronized`
	private __gshared ThreadEventsTy threadEvents;

	synchronized void notify()
	{
		foreach (_, tup; threadEvents)
			tup[0].events.trigger(tup[1], true);

		// reset at same time since all those thread events are done with now
		// expect the freshly awoken threads to free the resources we're removing the references to here
		threadEvents = ThreadEventsTy.init;
	}

	void wait() @Async
	{
		auto tid = Thread.getThis.id;
		EventID ev = void; // always assigned

		synchronized (this)
		{
			if (tid in threadEvents)
			{
				ev = threadEvents[tid][1];
				eventDriver.events.addRef(ev); // just in case two fibers wait this TEvent on the same thread :)
			}
			else
			{
				ev = eventDriver.events.create();
				threadEvents[tid] = tuple(cast(shared) eventDriver, ev);
			}
		}

		waitThreadEvent(ev);
		// threadEvents has now been cleared so this is safe to clean up.
		eventDriver.events.releaseRef(ev); // free resources like a good citizen
	}
}

// like TEvent but has a stateful triggered/untriggered value, idk if theres a good name for this
/* final shared @ThreadSafe class TStatefulEvent
{
@ThreadSafe:

	private bool triggered;
	private TEvent ev = new TEvent;

	synchronized void notify()
	{
		if (triggered)
			return; // i don't think this is necessary but can't hurt.

		triggered = true;

		ev.notify();
	}

	synchronized void reset()
	{
		if (triggered)
		{
			triggered = false;
			// safety: by here no fibers should have a waiting ec event anymore so we can wipe them.
			threadEvents = ThreadEventsTy.init;
		}
		// resetting an event that has not been triggered is a no-op! - otherwise it could hang fibers forever.
	}

	void wait() @Async
	{
		while (!triggered)
		{
			ev.wait();
			// if the thread event resolves, triggered may still be false because another fiber got there before us,
			// and reset the event. to prevent this case, we loop around again.
		}
	}
} */

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

		// wake up the fibers!
		notifyEv.notify();
	}

	synchronized bool tryWait()
	{
		if (count == 0)
			return false;

		count--;
		return true;
	}

	void wait() @Async
	{
		while (true)
		{
			// try and "wake" this fiber, only one thread and therefore fiber is allowed in this block at a time.
			synchronized (this)
			{
				if (count > 0)
				{
					count--;
					return;
				}
			}

			// someone else got here first! release the lock and wait until we're told theres new notifies.
			notifyEv.wait();
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
			// see if we get to take the mutex!
			synchronized (this)
			{
				if (!locked)
				{
					// we can lock!
					locked = true;
					return;
				}
			}

			// we didn't get it this time, efficiently wait for an unlock.
			unlockEv.wait();
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

		ReturnType!func tSynchronized(Parameters!func args) @Async @Synchronized
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
	}

	T get() @Async
	{
		// this pattern should be familiar by now, if not, read the comments on some earlier sync tools
		while (true)
		{
			synchronized (this)
			{
				if (hasValue)
					return value;
			}

			setEv.wait();
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

	synchronized void send(T val)
	{
		queue.insertBack(val);
		sendEv.notify();
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

			sendEv.wait();
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
