import std.stdio;
import std.datetime : dur, MonoTime;

import reactor;
import llevents;
import sync;

import eventcore.core : eventDriver;

import core.thread.osthread : Thread;

void main()
{
	entrypoint({
		// test of using a "thread" event on only one thread

		// fiber -> notify other thread
		auto evF2T = new TEvent;
		// other thread -> notify main thread fiber
		// otherwise the main thread exists and kills the other fiber!
		// god i HATE threads so much this is why rockhopper even exists
		auto evT2F = new TEvent;

		auto t = new Thread({
			try {
			entrypoint({
				writeln("2: before wait");
				evF2T.wait(); // this throws?

				writeln("hi");

				evT2F.notify();
				writeln("2: done");
			});
			} catch(Throwable e) { writeln (e);}
			writeln("2: exited reactor");
		}).start();

		spawn({
			sleep(dur!"msecs"(500));
			writeln("1: before notify");
			evF2T.notify();


			writeln("1: before wait");
			writeln(t.isRunning);
			evT2F.wait();
			sleep(dur!"msecs"(500));
			writeln("1: done");
		});
	});
}
