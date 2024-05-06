// `synct` has synchronization primitives like `syncf` that are thread safe, and will lock between fibers across
// multiple threads' reactors.
// these should be preferred over core.sync as instead of e.g. one thread being allowed to lock a mutex, only one fiber
// is allowed to lock that mutex, across many threads.

module rockhopper.rhapi.synct;

import rockhopper.core.llevents : waitThreadEvent;
import core.atomic : atomicOp;

// These need to be classes so we can use `synchronized(this)` and `synchronized` members

shared class TEvent
{

	import eventcore.core : eventDriver;
	import eventcore.driver : EventID, EventDriver;
	import std.typecons : Tuple, tuple;
	import core.thread.osthread : Thread;

	alias ThreadEventsTy = Tuple!(shared(EventDriver), EventID)[typeof(Thread.getThis.id)];

	shared bool triggered;
	// you may only await an event from the thread that created it, so we need one event per thread
	shared ThreadEventsTy threadEvents;

	import std.stdio;

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

	void wait()
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

shared class TSemaphore
{
	import core.atomic : atomicOp;

	private shared uint count;
	private shared TEvent notifyEv = new TEvent;

	/* this()
	{
		notifyEv = new TEvent;
	} */

	synchronized void notify()
	{
		atomicOp!"+="(count, 1);

		// notify this event when a new notify is sent
		// and reset it after each wait.
		notifyEv.notify();
	}

	synchronized bool tryWait()
	{
		if (count == 0)
			return false;

		atomicOp!"-="(count, 1);
		notifyEv.reset(); // in case nobody else is waiting, reset it ready for next time
		return true;
	}

	void wait()
	{
		// check if we can go immediately
		synchronized (this)
		{
			if (count > 0)
			{
				notifyEv.reset(); // must have been triggered, likely not cleared up.

				atomicOp!"-="(count, 1);
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
					atomicOp!"-="(count, 1);
					return;
				}
			}
			// count was not greater than zero, so someone else got here first!
			// we let go of the lock and get back to waiting.
		}
	}
}
