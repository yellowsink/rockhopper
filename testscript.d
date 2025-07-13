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
import std.conv : to;
import std.string : representation, assumeUTF;
import std.socket : parseAddress;
import eventcore.driver : ConnectStatus, IOStatus, IOMode;

import rockhopper.core;
import rockhopper.rhapi;

import eventcore.core : eventDriver;

import core.thread.osthread : Thread;

mixin rhMain!({

	StreamListen sl;
	sl.addr = parseAddress("::1", 8080);
	sl.registerListen();

	while (true)
	{
		writeln("waiting for conn...");
		// listen for incoming tcp connections
		auto stream = sl.wait();
		writeln("new connection accepted!");

		spawn({
			// just clone this to be safe.
			auto s = stream[0];

			while (true)
			{
				writeln("in sleep loop! fd: ", s);
				//sleep(dur!"msecs"(300));

				auto res = streamWrite(s, "hi!\n".representation);

				if (res.status != IOStatus.ok)
				{
					writeln("err: ", res.status);
					break;
				}
			}
		});
	}
});
