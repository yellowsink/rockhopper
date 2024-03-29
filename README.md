# Rockhopper

A small async library for D, built on `core.thread.Fiber` and `eventcore`.

## Why fibers?

The case for fibers can seem hard to understand at first, but essentially the main points are
 - As you get something akin to an event loop, you don't have to do thread syncronization! All tasks share one thread.
 - Fibers make writing thread-like code while actually running on one thread very comfortable

## Why Rockhopper?

Fibers are not as easy to use as threads.
We can build our functionality on top of the `std.concurrency.FiberScheduler`, and you get something like this:
```d
scheduler = new FiberScheduler;

// run twice in parallel
scheduler.spawn({
  writeln("hi 1!");
  Thread.sleep(dur!"msecs"(250));
  writeln("bye 1");
});
scheduler.start({
  writeln("hi 2!");
  Thread.sleep(dur!"msecs"(250));
  writeln("bye 2");
});
```

...aaaaand that doesn't work!

Instead, you need to use the (quite non-obvious) sleep mechanism given to you by the scheduler:
```d
scheduler = new FiberScheduler;

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
});
```

ew! -And to top it off, while all fibers are sleeping, the scheduler busy-waits! That sucks! (Rockhopper fixes this.)

What if that looked more like this:
```d
import rockhopper : spawn, entrypoint, sleep;

entrypoint({
  spawn({
    writeln("hi 1!");
    sleep(dur!"msecs"(250));
    writeln("bye 1");
  });
  spawn({
    writeln("hi 2!");
    sleep(dur!"msecs"(250));
    writeln("bye 2");
  });
});
```

### I/O

Sleeping is the easy case. The scheduler provides a `wait` function to you.
For I/O, you're on your own.

Rockhopper gives you versions of many standard library functions, that yield your fiber instead of blocking the thread.
The eventcore library is used to make these fully efficient - while blocking on I/O the app will not use extraneous CPU,
and will not add latency.

The provided I/O functions have identical signatures, they are not task-based in any way.

## Indefinite execution

It is recommended to fire off a "main" fiber:
```d
import rockhopper : entrypoint, spawn;

main() { entrypoint(&mainAsync); }

mainAsync() {
  import rockhopper.io : File;

  auto stdin = File(std.stdio.stdin); // convert phobos File into rockhopper File
  foreach (line; stdin.byLine) { // byLine blocks the fiber now!
    // this fiber may outlive mainAsync(), and can run things on the thread while the main one is waiting for a line
    spawn({ doLongAsyncWork(line); });
  }
}
```

## "Joining" a fiber
You can wait for a fiber to complete with `waitFor`, thread-`join`-style.

```d
auto fiber = hop({ sleep(dur!"msecs"(500)); });
waitFor(fiber); // effectively just waits 500ms
```

## Roadmap

- [ ] Basic fiber management
- [ ] `sleep`
- [ ] `waitFor`
- [ ] wrappers around other common stdlib things
