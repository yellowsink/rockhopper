# Drawbacks of Rockhopper

There are a few reasons why Rockhopper may not be the best option for your application in particular.
This (obviously non-exhaustive) page goes over a few of those.

## Single-threaded reactor

The reactor implementation runs on only a single thread, by design.
This means that if you are, say, building a web server handling hundreds of thousands of requests on a 64-core server,
Rockhopper is going to waste 63/64ths of your potential processing power.

You can get around this by either spawning multiple threads with their own reactors, or by just using something designed
for it like vibe.

## Lack of cancellation

At present, Rockhopper does not include any cancellation mechanism, so if you wish to be able to interrupt something
partway-through, you're out of luck.

## Implicit yield

This is as much an upside as a downside. It is a conscious design choice that asynchronous functions implicitly yield
your fiber, as if you were blocking a thread, however this can be undesirable to some, who might prefer a more obvious
marker that they are causing their fiber to be suspended.

One option here is to make liberal use of tasks.

## `entrypoint` / `rhMain`

You cannot simply open your project and start using fibers.
Technically Rockhopper could be modified to get around this, but for the time being it is most sensible to make starting
the reactor explicit.

This has some side effects if you have libraries that provide callbacks, that for example, the reactor may complete and
exit before you call spawn.

Generally, just try to make sure you don't let all your fibers die, then try to spawn a new one.

## Heap allocation

Rockhopper is not the most efficient possible implementation, and does make some performance sacrifices for comfort.
For example, some eventcore APIs return values to you that are only valid within the callback, due to referencing
stack-allocated memory.
Where appropriate, Rockhopper just clones this to the heap to remove the limitation.

Also worth noting that the thread safe fiber sync primitives are not efficient. The single-threaded fiber ones are. :)

## Closures and stack references

You may find yourself writing code like this, especially using RAII types:

```d
entrypoint({
	auto p = Pipe.create(); // 1: create a pipe

	spawn({
		// 3: this callback is run now the reactor is free, but!
		// `p` now represents a freed pipe, and not only that, but
		// the pointer to `p` was is now something completely different due to being in the stack, so `p` is garbage!
		// so: undefined behaviour (most often a segv).
		p.writeStream.rawWrite([42]);
	});

	// 2: p goes out of scope and the files and memory are freed
});
```

This is not great, but there are a few ways of getting around this.

First is to `yield()` enough times to ensure that all relevant values are cloned - you could do this by copying every
struct you use into a closure-local variable right at the very top, only using those values from then on,
and `yield()`ing once after your spawn.

A less flaky way to do this would be to use some kind of synchronization tool to keep the spawning fiber alive until
the child fibers are finished - `FWaitGroup` is a nice option here, Go-style:

```d
entrypoint({
	auto p = Pipe.create(); // 1: create a pipe

	auto wg = FWaitGroup(1);
	spawn({
		// 3: this callback is run now, while p is still valid
		p.writeStream.rawWrite([42]);
	});

	// 2: wait group yields control
	wg.wait();

	// 4: p goes out of scope and the files and memory are freed
});
```

A more technical note about why this is like this: the D specification guarantees us that in this case `Pipe` will be kept
alive long enough for us to safely access it (20.19.2), but unfortunately while it's memory still exists, the destructor is
still called when it goes out of scope.

This leads to contradictory behaviour where the language is supposed to make sure that delegates' referenced variables are
not deallocated, but forgets to ensure that their lifetime was actually extended.
A minimum example that shows this behaviour without all the added complexity of fibers and rockhopper: https://godbolt.org/z/3oz5j8cfM
