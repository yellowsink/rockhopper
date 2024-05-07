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
import rockhopper.rhapi;

import eventcore.core : eventDriver;

import core.thread.osthread : Thread;

void main()
{
	entrypoint({

		shared sem = new TSemaphore;

		auto thread1 = spawnThread({
			writeln("hi from thread 1");

			sleep(dur!"msecs"(500));
			sem.notify();
		});

		auto thread2 = spawnThread({
			writeln("hi from thread 2");
		});

		joinThread(thread2);
		writeln("main thread: joined 2");

		sem.wait();
		writeln("main thread: 2 notified sem");
		joinThread(thread1);

	});
}
