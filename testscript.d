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
	import std.string : assumeUTF;

	entrypoint({

		auto socket = eventDriver.sockets.createDatagramSocket(parseAddress("127.0.0.1", 8080), null);

		writeln(socket);

		ubyte[32] buf;
		auto res = dgramReceive(socket, buf);

		writeln(res, buf.assumeUTF);

		eventDriver.sockets.releaseRef(socket);
	});
}
