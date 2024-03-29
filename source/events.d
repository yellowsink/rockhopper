module events;

import reactor : FiberBlocker, awaitBlocker;
import eventcore.core : eventDriver;

import std.datetime : Duration, dur;
void sleep(Duration d)
{

  // 0ms repeat = don't repeat
  auto timer = eventDriver.timers.create();
  eventDriver.timers.set(timer, d, dur!"msecs"(0));

  awaitBlocker(FiberBlocker.sleep(timer));
}
