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
import eventcore.driver : IOMode, IOStatus, FileOpenMode;

Tuple!(IOStatus, ulong) fileRead(string path, ulong oset, ubyte[] buffer/* , IOMode mode */)
{
  // TODO: use async open, or use dlang File type somehow
  auto fd = eventDriver.files.open(path, FileOpenMode.read);
  alias mode = IOMode.once;

  return awaitBlocker(FiberBlocker.fileRead(tuple(fd, oset, buffer, mode))).fileReadValue;
}
