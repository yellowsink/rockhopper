module events;

import reactor : awaitBlocker;
import blockers : FiberBlocker, BlockerFileOpen, BlockerFileRead, BlockerReturnFileOpen, BlockerReturnFileRead;
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

import std.stdio : File;
import eventcore.driver : IOMode, FileFD;
public import eventcore.driver : FileOpenMode, OpenStatus, IOStatus;

BlockerReturnFileOpen fileOpen(string path, FileOpenMode mode)
{
  return awaitBlocker(FiberBlocker.fileOpen(BlockerFileOpen(path, mode))).fileOpenValue;
}

BlockerReturnFileRead fileRead(FileFD fd, ulong oset, ubyte[] buffer/* , IOMode mode */)
{
  alias mode = IOMode.once;

  return awaitBlocker(FiberBlocker.fileRead(BlockerFileRead(fd, oset, buffer, mode))).fileReadValue;
}
