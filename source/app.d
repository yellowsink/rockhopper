import std.stdio;

import std.concurrency : scheduler, FiberScheduler;
import core.thread.osthread : Thread;
import core.sync.mutex : Mutex;
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
  auto m = new Mutex;
  auto cond = scheduler.newCondition(m);
  new Thread({
    Thread.sleep(dur!"msecs"(d));

  }).start();
}

void main()
{
  // set up the scheduler, in this case, one backed by fibers
  scheduler = new FiberScheduler;

  void queueTask(int x) {
    scheduler.spawn({ writeln("hi from ", x); schedulerSleep(10_000); writeln("bye from ", x); });
  }

  // start a few tasks on the scheduler
  for (auto i = 0; i < 5; i++)
    queueTask(i);

  scheduler.start({});

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
