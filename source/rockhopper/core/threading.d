// `threading` contains fundamental threading utilities akin to the functions in `reactor`.

module rockhopper.core.threading;

import rockhopper.core.reactor : entrypoint, spawn;
import rockhopper.core.llevents : waitThreadEvent;
import rockhopper.core.uda : Async;

import eventcore.driver : EventDriver;
import eventcore.core : eventDriver;
import core.thread.osthread : Thread;
import std.typecons : Tuple, tuple;

struct ThreadHandle
{
	Thread th;
	shared(EventDriver) ed;

	void join() { joinThread(th); }

	void spawn(void delegate() fn)
	{
		assert(th.isRunning, "cannot spawn in a thread that is finished");
		spawnInThread(ed, fn);
	}
}

// spawns a new thread and runs the given function as a fiber in that thread's reactor
ThreadHandle spawnThread(void delegate() fn) @Async
{
	auto ev = eventDriver.events.create();
	shared sd = cast(shared) eventDriver;

	shared(EventDriver) res;

	auto t = new Thread({
		// send over a shared reference to this driver
		res = cast(shared) eventDriver;
		// tell the other thread that that's done
		sd.events.trigger(ev, true);

		// run the fiber!
		entrypoint(fn);
	}).start();

	assert(t !is null);

	// wait for `res` to be set
	waitThreadEvent(ev);
	assert(res !is null, "after the second thread fires the event, it should have send it's driver too.");

	return ThreadHandle(t, res);
}

private void _spawnInThread_springboard(void delegate() f) @trusted nothrow
{
	try
	{
		spawn(f);
	}
	catch (Exception e)
	{
		try
		{
			import std.stdio : stderr;

			stderr.writeln("[rockhopper.core.threading.spawnInThread] failed to spawn fiber in remote thread: ", e);
		}
		catch (Exception)
		{
			// oh nuts.
			assert(0);
		}
	}
}

// runs the fiber in another thread's event loop
// REQUIRES that that thread's event loop is already running! if `entrypoint` has exited, this won't work.
void spawnInThread(shared(EventDriver) ed, void delegate() fn)
{
	ed.core.runInOwnerThread(&_spawnInThread_springboard, fn);
}

// waits for a thread to exit asynchronously
void joinThread(Thread th) @Async
{
	auto ev = eventDriver.events.create();
	shared ed = cast(shared) eventDriver;

	// create an event that triggers when `th` exits
	auto t = new Thread({
		th.join();

		ed.events.trigger(ev, true);
	}).start();

	// wait for it, then clean up `t`
	waitThreadEvent(ev);
	t.join();
}
