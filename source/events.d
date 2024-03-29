module events;

import reactor : FiberBlocker, awaitBlocker;
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

Tuple!(FileFD, OpenStatus) fileOpen(string path, FileOpenMode mode)
{
  return awaitBlocker(FiberBlocker.fileOpen(tuple(path, mode))).fileOpenValue;
}

Tuple!(IOStatus, ulong) fileRead(FileFD fd, ulong oset, ubyte[] buffer/* , IOMode mode */)
{
  alias mode = IOMode.once;

  return awaitBlocker(FiberBlocker.fileRead(tuple(fd, oset, buffer, mode))).fileReadValue;
}
