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
		auto vtask = tSpawn({
			writeln("task says hi");
			sleep(dur!"msecs"(500));
		}).then({
			writeln("async continuation!");
		});

		auto itask = tSpawn({
			writeln("new task here");
			return 5;
		}).then((int v) => v > 6); // continuations can modify the value

		vtask.waitRes();

		writeln(itask.waitRes());
	});
}
