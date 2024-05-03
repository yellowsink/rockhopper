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
		StreamListen l;
		l.addr = parseAddress("::1", 8080);

		l.register();
		auto opened = l.wait();
		writeln("got connection");
		l.cleanup();

		import std.string : assumeUTF;

		ubyte[16] buf;

		auto res = streamRead(opened[0], buf);

		writeln(res, assumeUTF(buf));

		eventDriver.sockets.releaseRef(opened[0]);

	});
}
