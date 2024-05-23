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

		auto p = Pipe.create();
		p.writeEnd.rawWrite(representation("yo!"));

		ubyte[3] buf;
		p.readEnd.rawRead(buf);
		writeln(assumeUTF(buf));

	});
}

