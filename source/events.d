module events;

// general imports
import reactor : awaitBlocker;
import blockers;
import eventcore.core : eventDriver;
import std.typecons : Tuple, tuple;

// dns related imports
//public import eventcore.driver : DNSStatus, RefAddress;

// file/pipe related imports
import eventcore.driver : IOMode, FileFD, PipeFD;
public import eventcore.driver : FileOpenMode, OpenStatus, CloseStatus, IOStatus;

// signal related imports
public import eventcore.driver : SignalStatus;

// sleep imports
import std.datetime : Duration, dur;

/* BlockerReturnNsLookup nsLookup(string name)
{
	return awaitBlocker(FiberBlocker.nsLookup(name)).nsLookupValue;
} */

BlockerReturnFileOpen fileOpen(string path, FileOpenMode mode)
{
  return awaitBlocker(FiberBlocker.fileOpen(BlockerFileOpen(path, mode))).fileOpenValue;
}

CloseStatus fileClose(FileFD fd)
{
	return awaitBlocker(FiberBlocker.fileClose(fd)).fileCloseValue;
}

BlockerReturnRW fileRead(FileFD fd, ulong oset, ubyte[] buffer/* , IOMode mode */)
{
  alias mode = IOMode.once;

  return awaitBlocker(FiberBlocker.fileRead(BlockerFileRead(fd, oset, buffer, mode))).rwValue;
}

// TODO: pipes are an absolute mess, if you don't close them etc they will just cause resource leak chaos
//       we need a wrapper around them like phobos has File instead of FILE*
//       unless we just make that part of the higher level api and the raw events api is just an impl detail... hm.
BlockerReturnRW pipeRead(PipeFD fd, ubyte[] buffer/* , IOMode mode */)
{
  alias mode = IOMode.once;

  return awaitBlocker(FiberBlocker.pipeRead(BlockerPipeRead(fd, 0, buffer, mode))).rwValue;
}

BlockerReturnRW fileWrite(FileFD fd, ulong oset, const(ubyte)[] buffer/* , IOMode mode */)
{
	alias mode = IOMode.once;

	return awaitBlocker(FiberBlocker.fileWrite(BlockerFileWrite(fd, oset, buffer, mode))).rwValue;
}

BlockerReturnRW pipeWrite(PipeFD fd, const(ubyte)[] buffer/* , IOMode mode */)
{
	alias mode = IOMode.once;

	return awaitBlocker(FiberBlocker.pipeWrite(BlockerPipeWrite(fd, 0, buffer, mode))).rwValue;
}

SignalStatus signalTrap(int sig)
{
	auto result = awaitBlocker(FiberBlocker.signalTrap(sig)).signalTrapValue;
	eventDriver.signals.releaseRef(result.slID);
	return result.status;
}

void sleep(Duration d)
{

	// 0ms repeat = don't repeat
	auto timer = eventDriver.timers.create();
	eventDriver.timers.set(timer, d, dur!"msecs"(0));

	awaitBlocker(FiberBlocker.sleep(timer));
}
