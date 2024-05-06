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

		auto t1 = tSpawn({ sleep(dur!"msecs"(500)); return 5; });

		auto t2 = completedTask("yo");

		auto t3 = completedTask(3);

		waitAnyTask!(t1, t2);

	});
}
