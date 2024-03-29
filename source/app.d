import std.stdio;
import std.datetime : dur;
import core.thread.fiber : Fiber;

import reactor : reactor, Reactor, WrappedFiber, FiberBlocker;

void quickdirtytest_sleep(ulong ms)
{
  import eventcore.core : eventDriver;

  auto timer = eventDriver.timers.create();
  // 0ms repeat = don't repeat
  eventDriver.timers.set(timer, dur!"msecs"(ms), dur!"msecs"(0));

  reactor.currentFiber.currentBlocker = FiberBlocker.sleep(timer);
  reactor.currentFiber.blockerResult.nullify();

  while (reactor.currentFiber.blockerResult.isNull)
    Fiber.yield();
}

WrappedFiber quickdirtytest_makefiber(void delegate() fn)
{
  auto f = new Fiber(fn);
  auto wf = new WrappedFiber;
  wf.fiber = f;
  return wf;
}

void main()
{
  reactor.enqueueFiber(quickdirtytest_makefiber({
    writeln("i'm number 1! hi!");
    quickdirtytest_sleep(2500);
    writeln("number 1 slept for 2.5s");
  }));

  reactor.enqueueFiber(quickdirtytest_makefiber({
    writeln("i'm number 2! hi!");
    quickdirtytest_sleep(4000);
    writeln("number 2 slept for 4s");
  }));

  reactor.loop();
}
