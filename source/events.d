module events;

import reactor : awaitBlocker;
import blockers;
import eventcore.core : eventDriver;
import std.typecons : Tuple, tuple;

import std.datetime : Duration, dur;
void sleep(Duration d)
{

  // 0ms repeat = don't repeat
  auto timer = eventDriver.timers.create();
  eventDriver.timers.set(timer, d, dur!"msecs"(0));

  awaitBlocker(FiberBlocker.sleep(timer));
}

import eventcore.driver : IOMode, FileFD;
public import eventcore.driver : FileOpenMode, OpenStatus, IOStatus;

BlockerReturnFileOpen fileOpen(string path, FileOpenMode mode)
{
  return awaitBlocker(FiberBlocker.fileOpen(BlockerFileOpen(path, mode))).fileOpenValue;
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
