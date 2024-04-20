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
		auto eepyTask = taskify!sleep(dur!"seconds"(5));
		auto tBefore = MonoTime.currTime;

		eepyTask.waitRes(); // void

		writeln("eeped for ", MonoTime.currTime - tBefore);
	});
}