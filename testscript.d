#!/usr/bin/env dub
/+ dub.sdl:
	name "rockhopper-testing-script"
	dependency "rockhopper" path="."
	dependency "eventcore" version="~>0.9.29"
+/
module testscript;

// this script is used for testing rockhopper, and can either be ran with `./testscript.d`, or `dub testscript.d`

import std.stdio;
import std.datetime : dur, MonoTime;

import rockhopper.core;
import rockhopper.sync;
import rockhopper.task;

import eventcore.core : eventDriver;

import core.thread.osthread : Thread;

void main()
{
	entrypoint({
		auto ev = new TEvent;

		auto thread2 = new Thread({
			entrypoint({
				ev.wait();
				writeln("yay 2!");
			});
		}).start();

		auto thread3 = new Thread({
			entrypoint({
				ev.wait();
				writeln("yay 3!");
			});
		}).start();

		auto thread4 = new Thread({
			entrypoint({
				writeln("helo");
				Thread.sleep(dur!"seconds"(2));
				ev.notify();
			});
		}).start();

		thread2.join();
		thread3.join();
		thread4.join();
	});
}
