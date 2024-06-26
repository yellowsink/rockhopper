// `llevents` contains the lowest level APIs for interacting with rockhopper, other than using the reactor directly.
//            does not cover all operations, as some things can be done synchronously from `eventDriver`.
module rockhopper.core.llevents;

// TODO: when all of these are wrapped at a high level, check the docs for which need fSynchronized!

// general imports
import rockhopper.core.reactor : llawait, yield;
import rockhopper.core.uda : Async;
// yield should only be used for the socket wrappers, all others should use llawait only
import rockhopper.core.suspends;
import eventcore.core : eventDriver;
import std.typecons : Tuple, tuple;

// dns related imports
/* public */ import eventcore.driver : DNSStatus, RefAddress;

// thread event related imports
import eventcore.driver : EventID;

// file/pipe related imports
import eventcore.driver : IOMode, FileFD, PipeFD;
/* public */ import eventcore.driver : FileOpenMode, OpenStatus, CloseStatus, IOStatus;

// process related imports
/* public */ import eventcore.driver : Process, ProcessID;

// signal related imports
/* public */ import eventcore.driver : SignalStatus;

// socket related imports
import eventcore.driver : StreamSocketFD, StreamListenSocketFD, DatagramSocketFD;
/* public */ import eventcore.driver : ConnectStatus, StreamListenOptions, RefAddress;
import std.socket : Address;

// sleep related imports
import std.datetime : Duration, dur;

SRStreamConnect streamConnect(Address peer, Address bind) @Async
{
	return llawait(SuspendSend.streamConnect(SSStreamConnect(peer, bind))).streamConnectValue;
}

struct StreamListen
{
	import std.socket : Address, UnknownAddress;
	import std.typecons : Nullable, tuple, Tuple;

	import rockhopper.core.reactor : cloneRefAddress;

	@disable this(ref StreamListen); // prevent implicit copying

	Address addr;
	StreamListenOptions opts = StreamListenOptions.defaults;
	Nullable!StreamListenSocketFD fd;

	Tuple!(StreamSocketFD, RefAddress)[] sockets;

	void registerListen()
	{
		assert(fd.isNull);

		fd = eventDriver.sockets.listenStream(addr, opts, (_fd, sfd, ad) nothrow {
			assert(_fd == fd);

			sockets ~= tuple(sfd, cloneRefAddress(ad));
		});
	}

	// uses waitForConnections instead of listenStream, required you bring your own fd, ignores this.addr and this.opts.
	void registerWaitConns(StreamListenSocketFD listenfd)
	{
		assert(fd.isNull);
		fd = listenfd;

		eventDriver.sockets.waitForConnections(listenfd, (_fd, sfd, ad) nothrow {
			assert(_fd == fd);

			sockets ~= tuple(sfd, cloneRefAddress(ad));
		});
	}

	void cleanup()
	{
		assert(!fd.isNull);
		eventDriver.sockets.releaseRef(fd.get);
	}

	Tuple!(StreamSocketFD, RefAddress) wait() @Async
	{
		while (sockets is null || !sockets.length) yield();

		auto s = sockets[0];
		sockets = sockets[1 .. $];
		return s;
	}
}

SRRW streamRead(StreamSocketFD fd, ubyte[] buf, IOMode mode = IOMode.once) @Async
{
	return llawait(SuspendSend.streamRead(SSStreamRead(fd, 0, buf, mode))).rwValue;
}

IOStatus streamWaitForData(StreamSocketFD fd) @Async
{
	return streamRead(fd, []).status;
}

SRDgramSendReceive dgramReceive(DatagramSocketFD fd, ubyte[] buf, IOMode mode = IOMode.once) @Async
{
	return llawait(SuspendSend.dgramReceive(SSDgramReceive(fd, 0, buf, mode))).dgramSendReceiveValue;
}

SRDgramSendReceive dgramSend(DatagramSocketFD fd, const(ubyte)[] buf, Address target, IOMode mode = IOMode.once) @Async
{
	return llawait(SuspendSend.dgramSend(SSDgramSend(fd, buf, mode, target))).dgramSendReceiveValue;
}

SRRW streamWrite(StreamSocketFD fd, const(ubyte)[] buf, IOMode mode = IOMode.once) @Async
{
	return llawait(SuspendSend.streamWrite(SSStreamWrite(fd, 0, buf, mode))).rwValue;
}

SRNsLookup nsLookup(string name) @Async
{
	return llawait(SuspendSend.nsLookup(name)).nsLookupValue;
}

void waitThreadEvent(EventID evid) @Async
{
	llawait(SuspendSend.threadEvent(evid));
}

SRFileOpen fileOpen(string path, FileOpenMode mode) @Async
{
	return llawait(SuspendSend.fileOpen(SSFileOpen(path, mode))).fileOpenValue;
}

// this always returns instantly, btw
// https://github.com/vibe-d/eventcore/blob/515edf9b7ebf47d08b0cec8a7a5ae2cced30be71/source/eventcore/drivers/threadedfile.d#L250
// therefore it doesn't *really* need to go via the reactor, but oh well. Plus releaseref works too.
CloseStatus fileClose(FileFD fd) @Async
{
	return llawait(SuspendSend.fileClose(fd)).fileCloseValue;
}

SRRW fileRead(FileFD fd, ulong oset, ubyte[] buffer, IOMode mode = IOMode.once) @Async
{
	return llawait(SuspendSend.fileRead(SSFileRead(fd, oset, buffer, mode))).rwValue;
}

SRRW pipeRead(PipeFD fd, ubyte[] buffer, IOMode mode = IOMode.once) @Async
{
	return llawait(SuspendSend.pipeRead(SSPipeRead(fd, 0, buffer, mode))).rwValue;
}

SRRW fileWrite(FileFD fd, ulong oset, const(ubyte)[] buffer, IOMode mode = IOMode.once) @Async
{
	return llawait(SuspendSend.fileWrite(SSFileWrite(fd, oset, buffer, mode))).rwValue;
}

SRRW pipeWrite(PipeFD fd, const(ubyte)[] buffer, IOMode mode = IOMode.once) @Async
{
	return llawait(SuspendSend.pipeWrite(SSPipeWrite(fd, 0, buffer, mode))).rwValue;
}

int processWait(ProcessID pid) @Async
{
	return llawait(SuspendSend.procWait(pid)).procWaitValue;
}

SignalStatus signalTrap(int sig) @Async
{
	auto result = llawait(SuspendSend.signalTrap(sig)).signalTrapValue;
	eventDriver.signals.releaseRef(result.slID);
	return result.status;
}

void sleep(Duration d) @Async
{

	// 0ms repeat = don't repeat
	auto timer = eventDriver.timers.create();
	eventDriver.timers.set(timer, d, dur!"msecs"(0));

	llawait(SuspendSend.sleep(timer));
}
