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
		import std.socket : parseAddress;
		import std.string : representation; // string to bytes

		StreamListen listener;
		listener.addr = parseAddress("::1", 8080);
		listener.registerListen();

		// say hi to 3 people who connect to us
		for (auto i = 0; i < 3; i++)
		{
			auto stream = listener.wait();

			spawn({ streamWrite(stream[0], representation("hey there!")); eventDriver.sockets.releaseRef(stream[0]); });
		}

		listener.cleanup();
	});
}
