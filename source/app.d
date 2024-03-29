import std.stdio;
import std.datetime : dur;
import core.thread.fiber : Fiber;

void main()
{
  import reactor : reactor;

  void quickdirtytest_sleep(ulong ms)
  {
    import eventcore.core : eventDriver;
    auto timer = eventDriver.timers.create();
    // 0ms repeat = don't repeat
    eventDriver.timers.set(timer, dur!"msecs"(ms), dur!"msecs"(0));

    reactor.currentFiber.currentBlocker = reactor.FiberBlocker.sleep(timer);
    reactor.currentFiber.blockerResult.nullify();

    while (reactor.currentFiber.blockerResult.isNull) Fiber.yield();
  }

  void quickdirtytest_makefiber(void delegate() fn)
  {
    auto f = new Fiber(&fn);
    auto wf = reactor.WrappedFiber.init;
    wf.fiber = f;
    return wf;
  }

  reactor.enqueueFiber();
}
