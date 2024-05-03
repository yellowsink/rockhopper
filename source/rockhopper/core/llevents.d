// `llevents` contains the lowest level APIs for interacting with rockhopper, other than using the reactor directly.
//            does not cover all operations, as some things can be done synchronously from `eventDriver`.
module rockhopper.core.llevents;

// general imports
import rockhopper.core.reactor : llawait;
import rockhopper.core.suspends;
import eventcore.core : eventDriver;
import std.typecons : Tuple, tuple;

// dns related imports
//public import eventcore.driver : DNSStatus, RefAddress;

// thread event related imports
import eventcore.driver : EventID;

// file/pipe related imports
import eventcore.driver : IOMode, FileFD, PipeFD;
public import eventcore.driver : FileOpenMode, OpenStatus, CloseStatus, IOStatus;

// process related imports
public import eventcore.driver : Process, ProcessID;

// signal related imports
public import eventcore.driver : SignalStatus;

// sockets stuff
import eventcore.driver : StreamSocketFD;
//public import eventcore.driver : ConnectStatus;
import std.socket : Address;

SRSockConnect sockConnect(Address peer, Address bind)
{
	return llawait(SuspendSend.sockConnect(SSSockConnect(peer, bind))).sockConnectValue;
}

// sleep imports
import std.datetime : Duration, dur;

/* SRNsLookup nsLookup(string name)
{
	return llawait(SuspendSend.nsLookup(name)).nsLookupValue;
} */

void waitThreadEvent(EventID evid)
{
	llawait(SuspendSend.threadEvent(evid));
}

SRFileOpen fileOpen(string path, FileOpenMode mode)
{
	return llawait(SuspendSend.fileOpen(SSFileOpen(path, mode))).fileOpenValue;
}

CloseStatus fileClose(FileFD fd)
{
	return llawait(SuspendSend.fileClose(fd)).fileCloseValue;
}

SRRW fileRead(FileFD fd, ulong oset, ubyte[] buffer /* , IOMode mode */ )
{
	alias mode = IOMode.once;

	return llawait(SuspendSend.fileRead(SSFileRead(fd, oset, buffer, mode))).rwValue;
}

// TODO: pipes are an absolute mess, if you don't close them etc they will just cause resource leak chaos
//       we need a wrapper around them like phobos has File instead of FILE*
//       unless we just make that part of the higher level api and the raw events api is just an impl detail... hm.
SRRW pipeRead(PipeFD fd, ubyte[] buffer /* , IOMode mode */ )
{
	alias mode = IOMode.once;

	return llawait(SuspendSend.pipeRead(SSPipeRead(fd, 0, buffer, mode))).rwValue;
}

SRRW fileWrite(FileFD fd, ulong oset, const(ubyte)[] buffer /* , IOMode mode */ )
{
	alias mode = IOMode.once;

	return llawait(SuspendSend.fileWrite(SSFileWrite(fd, oset, buffer, mode))).rwValue;
}

SRRW pipeWrite(PipeFD fd, const(ubyte)[] buffer /* , IOMode mode */ )
{
	alias mode = IOMode.once;

	return llawait(SuspendSend.pipeWrite(SSPipeWrite(fd, 0, buffer, mode))).rwValue;
}

int processWait(ProcessID pid)
{
	return llawait(SuspendSend.procWait(pid)).procWaitValue;
}

SignalStatus signalTrap(int sig)
{
	auto result = llawait(SuspendSend.signalTrap(sig)).signalTrapValue;
	eventDriver.signals.releaseRef(result.slID);
	return result.status;
}

void sleep(Duration d)
{

	// 0ms repeat = don't repeat
	auto timer = eventDriver.timers.create();
	eventDriver.timers.set(timer, d, dur!"msecs"(0));

	llawait(SuspendSend.sleep(timer));
}
