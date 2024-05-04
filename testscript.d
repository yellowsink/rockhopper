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
import rockhopper.rhapi.sync;
import rockhopper.rhapi.task;

import eventcore.core : eventDriver;

import core.thread.osthread : Thread;

void main()
{
	import std.socket : parseAddress;
	import std.string : assumeUTF, representation;
	import eventcore.driver : FileOpenMode;

	entrypoint({
		// create a task
		auto t = tSpawn({ writeln("1"); sleep(dur!"msecs"(500)); writeln("3"); return "hello there"; });

		writeln("2");

		auto t2 = t.then((string s) { writeln(s); });

		t2.waitRes(); // wait for task to finish
		assert(t.isFinished);

		// bonus: create a task using an async function
		import rockhopper.core.llevents : nsLookup;

		auto dnsTask = taskify!nsLookup("google.com");

		writeln(dnsTask.waitRes);
	});
}
