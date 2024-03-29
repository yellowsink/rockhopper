import std.stdio;

import std.concurrency : scheduler, FiberScheduler;
import core.thread.osthread : Thread;
import core.atomic : atomicOp;
import std.datetime : dur;

void main()
{
  import reactor : reactor;

  writeln(reactor);

}
