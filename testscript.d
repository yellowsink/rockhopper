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

		auto p = Pipe.create();

		spawn({
			auto p2 = p;
			p2.readStream.rawRead(15).assumeUTF.writeln; // only reads 4
		});

		spawn({
			auto p2 = p;
			sleep(dur!"msecs"(500));
			p2.writeStream.rawWrite("test".representation);
		});

		// let the other fibers copy the reference BEFORE this one finishes
		// TODO: find some way around closures not causing a copy on creation, thus causing use-after-frees
		yield();
		yield();
	});
}

