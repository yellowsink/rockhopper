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

		auto done = false;

		import rockhopper.rhapi.file : File, FileOpenMode;

		File f;

		spawn({
			// whenever the main fiber yields, print out the underlying data in the struct.
			while (!done)
			{
				auto ptr = cast(ubyte*) &f;
				writeln(ptr[0 .. File.sizeof]);
				yield();
			}

			auto ptr = cast(ubyte*)&f;
			writeln(ptr[0 .. File.sizeof]);
		});

		f = File("testscript.d", FileOpenMode.read); // async construction!
		done = true;

	});
}

