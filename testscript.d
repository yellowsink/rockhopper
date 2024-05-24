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

		import rockhopper.rhapi.file;
		import std.string : representation, assumeUTF;
		import std.socket : parseAddress;
		import eventcore.driver : ConnectStatus, IOStatus;

		auto s = streamify(FileH("testscript.d", FileOpenMode.read));
		for (;;)
		{
			/* ubyte[128] buf;
			auto xfered = s.rawRead(buf); */
			auto buf = s.rawRead(128);
			writefln("xfered: %d, eof: %b", buf.length, s.isEof);

			if (s.isEof)
				writeln("last buffer: ", buf);

			if (s.isEof) break;
		}
	});
}

