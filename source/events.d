module events;

// general imports
import reactor : awaitBlocker;
import blockers;
import eventcore.core : eventDriver;
import std.typecons : Tuple, tuple;

// dns related imports
//public import eventcore.driver : DNSStatus, RefAddress;

// file related imports
import eventcore.driver : IOMode, FileFD;
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

BlockerReturnFileRW fileRead(FileFD fd, ulong oset, ubyte[] buffer/* , IOMode mode */)
{
  alias mode = IOMode.once;

  return awaitBlocker(FiberBlocker.fileRead(BlockerFileRead(fd, oset, buffer, mode))).fileRWValue;
}

BlockerReturnFileRW fileWrite(FileFD fd, ulong oset, const(ubyte)[] buffer/* , IOMode mode */)
{
	alias mode = IOMode.once;

	return awaitBlocker(FiberBlocker.fileWrite(BlockerFileWrite(fd, oset, buffer, mode))).fileRWValue;
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
