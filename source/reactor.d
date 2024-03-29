import std.typecons : Nullable;

private Nullable!Reactor _reactorBacking;

// Returns the reactor for the current thread.
public Reactor reactor() @property // @suppress(dscanner.confusing.function_attributes)
{
  if (_reactorBacking.isNull)
    _reactorBacking = new Reactor;

  return _reactorBacking.get;
}


/*private*/ class Reactor
{
  import std.typecons : Tuple, tuple;
  import core.thread.fiber : Fiber;
  import taggedalgebraic : TaggedUnion;
  import eventcore.core : eventDriver;
  import eventcore.driver : EventID, FileFD, PipeFD, IOMode, ProcessID, TimerID, ExitReason;
  import std.datetime : Duration;

  union _FiberBlockerRaw
  {
    // TODO: support not-timers
    //string nsLookup;
    //EventID ecThreadEvent;
    //Tuple!(FileFD, ulong, ubyte[], IOMode) fileRead;
    //Tuple!(FileFD, ulong, const(ubyte)[], IOMode) fileWrite;
    //Tuple!(PipeFD, ulong, ubyte[], IOMode) pipeRead;
    //Tuple!(PipeFD, ulong, const(ubyte)[], IOMode) pipeWrite;
    //ProcessID procWait;
    //int signalTrap;
    // TODO: sockets
    TimerID sleep;
    // TODO: directory watchers
  }
  alias FiberBlocker = TaggedUnion!_FiberBlockerRaw;

  class WrappedFiber
  {
    // the actual fiber
    Fiber fiber;
    // when unset, fiber is unblocked, when set, the blocker the fiber is waiting on
    Nullable!FiberBlocker currentBlocker;
    // if the current blocker has had its callback registered or not
    bool blockerRegistered;
    // when set, the result of the blocker (file data, etc) to be passed back to the fiber
    // TODO: support more than timers
    Nullable!TimerID blockerResult;
  }

  Nullable!WrappedFiber _currentFiber;
  // The currently executing fiber. Only valid to call inside of a running fiber.
  public inout(WrappedFiber) currentFiber() @property inout
  {
    return _currentFiber.get;
  }

  WrappedFiber[] fibers;

  //this(){}

  void enqueueFiber(WrappedFiber f)
  {
    fibers ~= f;
  }

  /*void setBlockerAndYield(FiberBlocker b)
  {
    // call site: within a fiber
    auto f = _currentFiber.get;
    assert(f.currentBlocker.isNull);
    f.currentBlocker = b;
    Fiber.yield();
  }*/

  void loop()
  {
    import std.array : array;
    import std.algorithm : map, filter;

    while (fibers.length)
    {
      // step 1: run all fibers (clone arr first to disambiguate mutation behaviour)
      foreach(f; fibers.array)
      {
        _currentFiber = f;
        f.fiber.call();
        _currentFiber.nullify();
      }

      // step 2: get fibers with blockers
      auto fibersToRegister = fibers.filter!(f => !f.currentBlocker.isNull && !f.blockerRegistered).array;

      // step 3: register callbacks
      foreach (f; fibersToRegister)
      {
        f.blockerRegistered = true;
        // TODO: support blockers other than `sleep`
        auto tid = f.currentBlocker.get.sleepValue;

        eventDriver.timers.wait(tid, (TimerID _timerId) nothrow {
          assert(tid == _timerId);

          // resolve blocker!
          f.currentBlocker.nullify();
          f.blockerRegistered = false;
          f.blockerResult = tid;
        });
      }

      // step 4: run event loop!
      // when processEvents is called with no params, will wait unless none are queued
      // instead, we want to just wait indefinitely if there are no queued events, so pass Duration.max
      auto eventFinishReason = eventDriver.core.processEvents(Duration.max);
      if (eventFinishReason == ExitReason.exited)
      {
        // TODO: does handling a user-requested exit need more finesse?
        break;
      }
      // TODO: what is ExitReason.idle?
      // ExitReason.outOfWaiters -> impossible due to Duration.max (or waits a super long time)
      // ExitReason.timeout -> impossible, or, the system has been runnning for Duration.max time and is about to explode
    }
  }
}