import std.stdio;

import std.concurrency : scheduler, FiberScheduler;
import core.thread.osthread : Thread;
import core.atomic : atomicOp;
import std.datetime : dur;

// NOTE:
// this is all just messing around and playing here
// none of this is rockhopper code.

void naiveSleep(ulong d)
{
  Thread.sleep(dur!"msecs"(d));
}

void schedulerSleep(ulong d)
{
  auto cond = scheduler.newCondition(null);
  cond.wait(dur!"msecs"(d));
}

void threadWaitSleep(ulong d)
{
  shared int done = 0;
  new Thread({
    Thread.sleep(dur!"msecs"(d));
    atomicOp!"+="(done, 1);
  }).start();

  auto cond = scheduler.newCondition(null);
  while (!done)
    cond.wait(dur!"msecs"(2)); // we'll just poll 2ms for now
}

void main()
{
  // set up the scheduler, in this case, one backed by fibers
  scheduler = new FiberScheduler;

  /* scheduler.spawn({
    for (int i = 0; i < 10; i++) {
      writeln("hi!");
      schedulerSleep(100);
    }
  }); */
  /* scheduler.start({
    writeln("hi");
    threadWaitSleep(500);
    writeln("wow!");
    schedulerSleep(500);
    writeln("sched.");
  }); */

scheduler.start({
  void queueTask(int x) {
    scheduler.spawn({ writeln("hi from ", x); schedulerSleep(1_000); writeln("bye from ", x); });
  }

  // start a few tasks on the scheduler
  for (auto i = 0; i < 5; i++)
    queueTask(i);
});
//  scheduler.start({});

/* scheduler = new FiberScheduler;

// run twice in parallel
scheduler.spawn({
  writeln("hi 1!");
  scheduler.newCondition(null).wait(dur!"msecs"(250));
  writeln("bye 1");
});
scheduler.start({
  writeln("hi 2!");
  scheduler.newCondition(null).wait(dur!"msecs"(250));
  writeln("bye 2");
}); */
}
