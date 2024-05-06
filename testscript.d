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
	shared sem = new TSemaphore;

	auto thread1 = new Thread({
		entrypoint({
			for (auto i = 0; i < 2; i++)
			{
				sem.wait();
				writeln("thread 1 wait");
			}
		});
	}).start();

	auto thread2 = new Thread({
		entrypoint({
			sem.wait();
			writeln("thread 2 wait");
		});
	}).start();

	entrypoint({
		for (auto i = 0; i < 3; i++)
		{
			sleep(dur!"seconds"(1));
			sem.notify();
		}
	});

	thread1.join();
	thread2.join();
}
