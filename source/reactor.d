// === PUBLIC API ===
import core.thread.fiber : Fiber;

public {
  void spawn(void delegate() fn)
  {
    reactor.enqueueFiber(fn);
  }

  void entrypoint(void delegate() fn)
  {
    spawn(fn);
    reactor.loop();
  }

  void entrypoint(void function() fn) { entrypoint({ fn(); }); }

  // Fiber.yield() for convenience
  alias yield = Fiber.yield;

  // return type must be the same as blockerResult
  // The function called to await on a blocker. You MUST use this function to do so.
  TimerID awaitBlocker(FiberBlocker bl)
  {
    assert(!reactor._currentFiber.isNull);
    auto cf = reactor._currentFiber.get;

    assert(cf.currentBlocker.isNull);
    cf.currentBlocker = bl;
    cf.blockerResult.nullify();

    while (cf.blockerResult.isNull) yield();
    return cf.blockerResult.get;
  }
}

// === FIBER BLOCKER TYPE ===

import std.typecons : Tuple, tuple;
import taggedalgebraic : TaggedUnion;
import eventcore.driver : EventID, FileFD, PipeFD, IOMode, ProcessID, TimerID, ExitReason;

private union _FiberBlockerRaw
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

public alias FiberBlocker = TaggedUnion!_FiberBlockerRaw;

// === LAZY INIT ===

import std.typecons : Nullable;

private {
  Nullable!Reactor _reactorBacking;

  Reactor reactor() @property // @suppress(dscanner.confusing.function_attributes)
  {
    if (_reactorBacking.isNull)
      _reactorBacking = new Reactor;

    return _reactorBacking.get;
  }
}

// === REACTOR IMPLEMENTATION ===

private class Reactor
{
  Nullable!WrappedFiber _currentFiber;

  WrappedFiber[] fibers;

  void enqueueFiber(void delegate() f)
  {
    fibers ~= new WrappedFiber(f);
  }

  void loop()
  {
    import eventcore.core : eventDriver;
    import std.array : array;
    import std.algorithm : map, filter;
    import std.datetime : Duration;

    while (fibers.length)
    {
      // step 1: run all fibers (clone arr first to disambiguate mutation behaviour)
      foreach(f; fibers.array)
      {
        _currentFiber = f;
        f.fiber.call();
        _currentFiber.nullify();
      }

      // step 2: remove finished fibers
      fibers = fibers.filter!(f => f.fiber.state != Fiber.State.TERM).array;

      // step 3: get fibers with blockers
      auto fibersToRegister = fibers.filter!(f => !f.currentBlocker.isNull && !f.blockerRegistered).array;

      // step 4: register callbacks
      foreach (f_; fibersToRegister)
      {
        // https://forum.dlang.org/post/wpnlxtpmsyltjjwmmctp@forum.dlang.org
        (f) {
          f.blockerRegistered = true;
          // TODO: support blockers other than `sleep`
          auto tid = f.currentBlocker.get.sleepValue;

          eventDriver.timers.wait(tid, (TimerID _timerId) nothrow{
            //debug { import std.stdio : writeln; try { writeln(tid); } catch (Exception) {} }
            //debug { import std.stdio : writeln; try { writeln(_timerId); } catch (Exception) {} }
            assert(tid == _timerId);

            // resolve blocker!
            f.currentBlocker.nullify();
            f.blockerRegistered = false;
            f.blockerResult = tid;
          });
        }(f_);
      }

      // step 5: run event loop!
      // when processEvents is called with no params, will wait unless none are queued
      // instead, we want to just wait indefinitely if there are no queued events, so pass Duration.max
      // TODO: what is ExitReason.idle?
      if (ExitReason.exited == eventDriver.core.processEvents(Duration.max)) break;
    }
  }

  class WrappedFiber
  {
    this(void delegate() fn)
    {
      fiber = new Fiber(fn);
    }

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
}