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
	import std.socket : parseAddress;

	entrypoint({
		writeln("opening socket");
		LLStreamListen s;
		s.addr = parseAddress("::1", 8080);

		s.register();

		spawn({
			while (true)
			{
				writeln(s.wait()[1]);
			}
		});

		sleep(dur!"seconds"(10));

		s.cleanup();

		writeln("cleaned up!");
	});
}
