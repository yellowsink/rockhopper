module reactor;

// === PUBLIC API ===
import core.thread.fiber : Fiber;

public {
	void spawn(void delegate() fn)
	{
		reactor.enqueueFiber(fn);
	}

	void entrypoint(void delegate() fn)
	{
		spawn(fn);
		reactor.loop();
	}

	void entrypoint(void function() fn) {
		entrypoint({
			fn();
		});
	}

	// Fiber.yield() for convenience
	alias yield = Fiber.yield;

	// return type must be the same as blockerResult
	// The function called to await on a blocker. You MUST use this function to do so.
	BlockerReturn awaitBlocker(FiberBlocker bl)
	{
		assert(!reactor._currentFiber.isNull);
		auto cf = reactor._currentFiber.get;

		assert(cf.currentBlocker.isNull);
		cf.currentBlocker = bl;
		cf.blockerResult.nullify();

		while (cf.blockerResult.isNull) yield();

		auto res = cf.blockerResult.get;
		cf.currentBlocker.nullify();
		cf.blockerRegistered = false;

		return res;
	}

	// bails out of the event loop *now*
	void earlyExit()
	{
		import eventcore.core : eventDriver;

		eventDriver.core.exit();
		yield();
	}
}

// === FIBER BLOCKER TYPE ===

import std.typecons : Tuple, tuple;
import taggedalgebraic : TaggedUnion;
import eventcore.driver : EventID, FileFD, PipeFD, IOMode, ProcessID, TimerID, ExitReason, IOStatus, FileOpenMode, OpenStatus;

private union _FiberBlockerRaw
{
	// TODO: implement more of these
	//string nsLookup;
	//EventID ecThreadEvent;
	Tuple!(string, FileOpenMode) fileOpen;
	Tuple!(FileFD, ulong, ubyte[], IOMode) fileRead;
	//Tuple!(FileFD, ulong, const(ubyte)[], IOMode) fileWrite;
	//Tuple!(PipeFD, ulong, ubyte[], IOMode) pipeRead;
	//Tuple!(PipeFD, ulong, const(ubyte)[], IOMode) pipeWrite;
	//ProcessID procWait;
	//int signalTrap;
	// TODO: sockets
	TimerID sleep;
	// TODO: directory watchers
}

public alias FiberBlocker = TaggedUnion!_FiberBlockerRaw;

private union _BlockerReturnRaw
{
	Tuple!(FileFD, OpenStatus) fileOpen;
	Tuple!(IOStatus, ulong) fileRead;
	Object sleep; // basically empty but pretty sure `void` will cause... issues.
}

public alias BlockerReturn = TaggedUnion!_BlockerReturnRaw;

// === LAZY INIT ===

import std.typecons : Nullable;

private {
	Nullable!Reactor _reactorBacking;

	Reactor reactor() @property // @suppress(dscanner.confusing.function_attributes)
	{
		if (_reactorBacking.isNull)
			_reactorBacking = new Reactor;

		return _reactorBacking.get;
	}
}

// === REACTOR IMPLEMENTATION ===

private class Reactor
{
	Nullable!WrappedFiber _currentFiber;

	WrappedFiber[] fibers;

	void enqueueFiber(void delegate() f)
	{
		fibers ~= new WrappedFiber(f);
	}

	void loop()
	{
		import eventcore.core : eventDriver;
		import std.array : array;
		import std.algorithm : map, filter;
		import std.datetime : Duration;

		while (fibers.length)
		{
			auto fiberCountBefore = fibers.length;
			// step 1: run all fibers (clone array to not loop over new fibers!)
			foreach (f; fibers.array)
			{
				_currentFiber = f;
				f.fiber.call();
				_currentFiber.nullify();
			}

			// step 1.5: handle new fibers!
			// if we have new fibers, don't stop and wait for the current fibers to finish blocking, there's more stuff to do!
			// instead, just loop back round to the start and keep going
			if (fibers.length > fiberCountBefore) continue;

			// step 2: remove finished fibers
			fibers = fibers.filter!(f => f.fiber.state != Fiber.State.TERM).array;

			// step 3: get fibers with blockers
			auto fibersToRegister = fibers.filter!(f => !f.currentBlocker.isNull && !f.blockerRegistered).array;

			// step 4: register callbacks
			foreach (f_; fibersToRegister)
			{
				// https://forum.dlang.org/post/wpnlxtpmsyltjjwmmctp@forum.dlang.org
					(f) {
					f.blockerRegistered = true;
					// TODO: support blockers other than `sleep`
					auto blocker = f.currentBlocker.get;

					final switch (blocker.kind)
					{
						case FiberBlocker.Kind.sleep:
							auto timid = blocker.sleepValue;
							eventDriver.timers.wait(timid, (TimerID _timerId) nothrow{
								assert(timid == _timerId);

								f.blockerResult = BlockerReturn.sleep(new Object);
							});
							break;

						case FiberBlocker.Kind.fileRead:
							auto fd = blocker.fileReadValue[0];
							auto oset = blocker.fileReadValue[1];
							auto buf = blocker.fileReadValue[2];
							auto mode = blocker.fileReadValue[3];

							eventDriver.files.read(fd, oset, buf, mode, (FileFD _fd, IOStatus status, ulong read) nothrow{
								assert(fd == _fd);

								f.blockerResult = BlockerReturn.fileRead(tuple(status, read));
							});
							break;

						case FiberBlocker.Kind.fileOpen:
							auto path = blocker.fileOpenValue[0];
							auto mode = blocker.fileOpenValue[1];

							eventDriver.files.open(path, mode, (FileFD fd, OpenStatus status) nothrow{
								f.blockerResult = BlockerReturn.fileOpen(tuple(fd, status));
							});
							break;
					}
				}(f_);
			}

			// step 5: run event loop!
			// when processEvents is called with no params, will wait unless none are queued
			// instead, we want to just wait indefinitely if there are no queued events, so pass Duration.max
			// TODO: what is ExitReason.idle?
			if (ExitReason.exited == eventDriver.core.processEvents(Duration.max)) break;
		}
	}

	class WrappedFiber
	{
		this(void delegate() fn)
		{
			fiber = new Fiber(fn);
		}

		Fiber fiber;
		// when unset, fiber is unblocked, when set, the blocker the fiber is waiting on
		Nullable!FiberBlocker currentBlocker;
		// if the current blocker has had its callback registered or not
		bool blockerRegistered;
		// when set, the result of the blocker (file data, etc) to be passed back to the fiber
		Nullable!BlockerReturn blockerResult;
	}
}
