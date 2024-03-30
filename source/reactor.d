module reactor;

// === PUBLIC API ===
import core.thread.fiber : Fiber;
import blockers : FiberBlocker, BlockerReturn;

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
		import eventcore.driver : ExitReason;
		import std.array : array;
		import std.algorithm : map, filter;
		import std.datetime : Duration;

		while (fibers.length)
		{
			// step 1: run all fibers (clone array to not loop over new fibers!)
			auto fibersBefore = fibers.array;
			foreach (f; fibersBefore)
			{
				_currentFiber = f;
				f.fiber.call();
			}
			_currentFiber.nullify();

			// step 2: check for new fibers!
			// if we have new fibers, don't stop and wait for the current fibers to finish blocking, there's more stuff to do!
			// instead, just loop back round to the start and keep going
			auto newFibersAdded = fibers.length > fibersBefore.length;

			// step 3: remove finished fibers from the list
			fibers = fibers.filter!(f => f.fiber.state != Fiber.State.TERM).array;

			// step 2.5: we have to remove finished fibers BEFORE we loop back around
			// otherwise, we .call() on a finished fiber - segfault on dmd and ldc, noop on gdc.
			if (newFibersAdded) continue;

			// step 4: register callbacks on fibers that need it
			foreach (f; fibers)
				registerCallbackIfNeeded(f);

			// step 5: run event loop!
			// when processEvents is called with no params, will wait unless none are queued
			// instead, we want to just wait indefinitely if there are no queued events, so pass Duration.max
			// TODO: what is ExitReason.idle?
			if (ExitReason.exited == eventDriver.core.processEvents(Duration.max)) break;
		}
	}

	private void registerCallbackIfNeeded(WrappedFiber f)
	{
		import eventcore.core : eventDriver;
		import blockers : BlockerReturnFileOpen, BlockerReturnFileRW, BlockerReturnSignalTrap;

		// don't register a callback if there is nothing to register, or it's already done.
		if (f.currentBlocker.isNull || f.blockerRegistered)
			return;

		f.blockerRegistered = true;
		auto genericBlocker = f.currentBlocker.get;

		final switch (genericBlocker.kind)
		{
		case FiberBlocker.Kind.sleep:
			auto timerId = genericBlocker.sleepValue;

			eventDriver.timers.wait(timerId, (_timerId) nothrow{
				assert(timerId == _timerId);

				f.blockerResult = BlockerReturn.sleep(new Object);
			});
			break;

		case FiberBlocker.Kind.fileOpen:
			auto b = genericBlocker.fileOpenValue;

			eventDriver.files.open(b.path, b.mode, (fd, status) nothrow{
				f.blockerResult = BlockerReturn.fileOpen(BlockerReturnFileOpen(fd, status));
			});
			break;

		case FiberBlocker.Kind.fileRead:
			auto b = genericBlocker.fileReadValue;

			eventDriver.files.read(b.fd, b.offset, b.buf, b.ioMode, (_fd, status, read) nothrow{
				assert(b.fd == _fd);

				f.blockerResult = BlockerReturn.fileRW(BlockerReturnFileRW(status, read));
			});
			break;

		case FiberBlocker.Kind.fileWrite:
			auto b = genericBlocker.fileWriteValue;

			eventDriver.files.write(b.fd, b.offset, b.buf, b.ioMode, (_fd, status, written) nothrow{
				assert(b.fd == _fd);

				f.blockerResult = BlockerReturn.fileRW(BlockerReturnFileRW(status, written));
			});
			break;

		case FiberBlocker.Kind.signalTrap:
			auto sig = genericBlocker.signalTrapValue;

			eventDriver.signals.listen(sig, (slID, status, _sigNum) {
				assert(_sigNum == sig);

				f.blockerResult = BlockerReturn.signalTrap(BlockerReturnSignalTrap(slID, status));
			});
			break;
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
