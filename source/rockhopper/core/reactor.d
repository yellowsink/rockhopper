// `reactor` contains the actual reactor implementation, and the thread-global reactor API
module rockhopper.core.reactor;

// === PUBLIC API ===
import core.thread.fiber : Fiber;
import rockhopper.core.suspends : SuspendSend, SuspendReturn;

public {
	void spawn(void delegate() fn)
	{
		reactor.enqueueFiber(fn);
	}

	void entrypoint(void delegate() fn)
	{
		assert(reactor.fibers.length == 0, "You can only have one entrypoint() call in flight at once on a reactor!");

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

	// return type must be the same as WrappedFiber.suspendResult
	// This function informs the reactor to pause your fiber and potentially entire thread on the given suspend.
	SuspendReturn llawait(SuspendSend bl)
	{
		assert(
			!reactor._currentFiber.isNull,
			"You cannot await a suspend if you're not in a fiber (hint: wrap your code in entrypoint({}))"
		);
		auto cf = reactor._currentFiber.get;

		assert(cf.currentSuspend.isNull);
		cf.currentSuspend = bl;
		cf.suspendResult.nullify();

		while (cf.suspendResult.isNull) yield();

		auto res = cf.suspendResult.get;
		cf.currentSuspend.nullify();
		cf.suspendRegistered = false;

		return res;
	}

	// bails out of the event loop *now*
	void earlyExit()
	{
		import eventcore.core : eventDriver;

		eventDriver.core.exit();

		if (!reactor._currentFiber.isNull)
			yield(); // causes an instant exit when called inside a fiber, or just causes it to exit ASAP from outside
	}
}

private Reactor reactor;

// === REACTOR IMPLEMENTATION ===

private struct Reactor
{
	import std.typecons : Nullable;

	// there should only ever be one reactor per thread, in TLS, and it is private to this module
	// so it should not EVER be copied, but to make sure it isn't, this specifically prevents that.
	// if this is ever a problem, reintroduce the old class lazy init thing but with a Reactor* instead.
	@disable this(ref Reactor);

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

			// step 6: run event loop!
			// when processEvents is called with no params, will wait unless none are queued
			// instead, we want to just wait indefinitely if there are no queued events, so pass Duration.max
			// double check that fibers still exist! if all exited, then this would just hang forever.
			if (fibers.length && ExitReason.exited == eventDriver.core.processEvents(Duration.max)) break;

			// ExitReason.exited -> earlyExit()
			//           .idle -> processed some events
			//           .outOfWaiters -> no fibers have registered suspends (e.g. yield() without a suspend)
			//           .timeout -> impossible, lol
		}
	}

	private void registerCallbackIfNeeded(WrappedFiber f)
	{
		import eventcore.core : eventDriver;

		// don't register a callback if there is nothing to register, or it's already done.
		if (f.currentSuspend.isNull || f.suspendRegistered)
			return;

		f.suspendRegistered = true;
		auto relevantSuspend = f.currentSuspend.get;

		final switch (relevantSuspend.kind) with (SuspendSend.Kind)
		{
		case nsLookup:
			// the mixin cannot handle this case due to needing to clone scoped resources
			auto v = relevantSuspend.nsLookupValue;

			eventDriver.dns.lookupHost(v, (_id, status, scope addrs) nothrow {
				import std.algorithm : map;
				import std.array : array;
				import rockhopper.core.suspends : SuspendReturn, SRNsLookup;

				auto escapedAddrs = addrs.map!(cloneRefAddress).array;

				f.suspendResult = SuspendReturn.nsLookup(SRNsLookup(status, escapedAddrs));
			});
			break;

		case threadEvent:
			mixin RegisterCallback!("threadEvent", "events.wait", ["v"], 0);
			MIXIN_RES();
			break;

		case fileOpen:
			mixin RegisterCallback!("fileOpen", "files.open", ["v.path", "v.mode"], 2, HandleArgumentPos.None, "SRFileOpen");
			MIXIN_RES();
			break;


		case fileClose:
			mixin RegisterCallback!("fileClose", "files.close", ["v"], 1);
			MIXIN_RES();
			break;

		case fileRead:
			mixin RegisterCallback!("fileRead", "files.read", ["v.fd", "v.offset", "v.buf", "v.ioMode"], 2, HandleArgumentPos.First, "SRRW", "rw");
			MIXIN_RES();
			break;

		case pipeRead:
			mixin RegisterCallback!("pipeRead", "pipes.read", ["v.fd", "v.buf", "v.ioMode"], 2, HandleArgumentPos.First, "SRRW", "rw");
			MIXIN_RES();
			break;

		case fileWrite:
			mixin RegisterCallback!("fileWrite", "files.write", ["v.fd", "v.offset", "v.buf", "v.ioMode"], 2, HandleArgumentPos.First, "SRRW", "rw");
			MIXIN_RES();
			break;

		case pipeWrite:
			mixin RegisterCallback!("pipeWrite", "pipes.write", ["v.fd", "v.buf", "v.ioMode"], 2, HandleArgumentPos.First, "SRRW", "rw");
			MIXIN_RES();
			break;

		case procWait:
			mixin RegisterCallback!("procWait", "processes.wait", ["v"], 1);
			MIXIN_RES();
			break;


		case signalTrap:
			mixin RegisterCallback!("signalTrap", "signals.listen", ["v"], 2, HandleArgumentPos.Last, "SRSignalTrap");
			MIXIN_RES();
			break;

		case streamConnect:
			mixin RegisterCallback!("streamConnect", "sockets.connectStream", ["v.peerAddress", "v.bindAddress"], 2, HandleArgumentPos.None, "SRStreamConnect");
			MIXIN_RES();
			break;

		case streamRead:
			mixin RegisterCallback!("streamRead", "sockets.read", ["v.fd", "v.buf", "v.ioMode"], 2, HandleArgumentPos.First, "SRRW", "rw");
			MIXIN_RES();
			break;

		case dgramReceive:
			// cannot use the mixin due to a refaddress that needs cloning
			auto v = relevantSuspend.dgramReceiveValue;

			eventDriver.sockets.receive(v.fd, v.buf, v.ioMode, (_fd, status, read, scope addr) nothrow{
				import rockhopper.core.suspends : SuspendReturn, SRDgramSendReceive;

				f.suspendResult = SuspendReturn.dgramSendReceive(SRDgramSendReceive(status, read, cloneRefAddress(addr)));
			});
			break;

		case dgramSend:
			// cannot use the mixin due to a refaddress that needs cloning
			auto v = relevantSuspend.dgramSendValue;

			eventDriver.sockets.send(v.fd, v.buf, v.ioMode, v.targetAddress, (_fd, status, written, scope addr) nothrow{
				import rockhopper.core.suspends : SuspendReturn, SRDgramSendReceive;

				assert(addr is null);

				f.suspendResult = SuspendReturn.dgramSendReceive(SRDgramSendReceive(status, written, null));
			});
			break;

		case streamWrite:
			mixin RegisterCallback!("streamWrite", "sockets.write", ["v.fd", "v.buf", "v.ioMode"], 2, HandleArgumentPos.First, "SRRW", "rw");
			MIXIN_RES();
			break;

		case sleep:
			mixin RegisterCallback!("sleep", "timers.wait", ["v"], 0);
			MIXIN_RES();
			break;
		}
	}

	// TODO: struct? maybe? perhaps...? to think about for later.
	class WrappedFiber
	{
		this(void delegate() fn)
		{
			fiber = new Fiber(fn);
		}

		Fiber fiber;
		// when unset, fiber is unblocked, when set, the suspend the fiber is waiting on
		Nullable!SuspendSend currentSuspend;
		// if the current suspend has had its callback registered or not
		bool suspendRegistered;
		// when set, the result of the suspend (file data, etc) to be passed back to the fiber
		Nullable!SuspendReturn suspendResult;
	}
}

// === MIXIN FOR NEATER REGISTERING OF CALLBACKS ===

// TODO: make registering callbacks more compile-time than this is already (maybe ct-ify all of suspends.d)
private enum HandleArgumentPos
{
	// this enum should ONLY exist at compile time or something has gone VERY wrong.
	None,
	First,
	Last
}

private mixin template RegisterCallback(
	// name of suspend enums, and name of function on the event driver
	string enumName, string edName,
	// args to event driver and back from callback (not including repeat)
	string[] edArgs, int cbArgCount,
	// if an arg of the callback is a repeat of the first param, where
	HandleArgumentPos hap = HandleArgumentPos.First,
	// if not "", the name of a function to pass the args to (to construct a struct or sm)
	string extraCons = "",
	// if the return type enum has a different name to the sender
	string returnOverride = ""
)
{
	import std.array : join, array;
	import std.range : iota;
	import std.algorithm : map;
	import std.conv : to;

	static assert(edArgs.length, "should be some arguments to eventDriver.*.*()");

	enum cbArgs = iota(0, cbArgCount).map!((n) => "__cbArg" ~ n.to!string).array;

	static if (hap == HandleArgumentPos.None)
		enum cbArgsPadded = cbArgs;
	else static if (hap == HandleArgumentPos.First)
		enum cbArgsPadded = ["__handle"] ~ cbArgs;
	else
		enum cbArgsPadded = cbArgs ~ ["__handle"];

	// you're only allowed to make declarations in a mixin template, not statements :(
	void MIXIN_RES()
	{
		auto v = mixin("relevantSuspend." ~ enumName ~ "Value");

		// for some reason the ide support hates using an IES so I won't
		enum sEdFuncName = "eventDriver." ~ edName;
		enum sEdArgs = edArgs.join(",");
		enum sCbargs = cbArgsPadded.join(",");
		// assume first argument to event driver is the one we're testing against
		enum sAssert = (hap == HandleArgumentPos.None ? "" : "assert(__handle==" ~ edArgs[0] ~ ");");
		enum sImportedExtraCons = "imported!\"rockhopper.core.suspends\"." ~ extraCons;
		enum sReturnVal = extraCons.length ? (sImportedExtraCons ~ "(" ~ cbArgs.join(",") ~ ")") : cbArgs.join(",");

		mixin(
			sEdFuncName ~ "(" ~ sEdArgs ~ ", (" ~ sCbargs ~ ") nothrow {"
				~ sAssert
				~ "f.suspendResult = SuspendReturn." ~ (returnOverride.length ? returnOverride : enumName) ~ "(" ~ sReturnVal ~ ");"
			~ "});"
		);
	}
}

// utility needed for implementation of both DNS and sockets, to help escape refaddresses outside of the scope.
import eventcore.driver : RefAddress;
public RefAddress cloneRefAddress(scope RefAddress src)
nothrow @trusted
{
	// oops!
	if (src is null) return null;

	version (Windows)
		import core.sys.windows.winsock2 : sockaddr_storage, sockaddr;
	else
		import core.sys.posix.sys.socket : sockaddr_storage, sockaddr;

	// heap memory to allow escaping instead of stack memory
	auto storage = new sockaddr_storage;
	// copy
	*storage = *(cast(sockaddr_storage*) src.name);

	// construct new refaddress
	return new RefAddress(cast(sockaddr*) storage, src.nameLen);
}
