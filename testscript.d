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
	enum AMOUNT = 100_000;

	writeln("spawning ", AMOUNT, " co-existent fibers on one reactor...");

	MonoTime before;
	MonoTime spawned;
	MonoTime exited;

	entrypoint({
		// yes, these fibers all immediately die, yes thats fine, they don't get a chance to run and hence die until
		// this one yields anyway.

		before = MonoTime.currTime;

		for (auto i = 0; i < AMOUNT; i++)
			spawn({});

		spawned = MonoTime.currTime;
	});

	exited = MonoTime.currTime;

	writeln("time to spawn:        ", spawned - before);
	writeln("time to exit reactor: ", exited - spawned);
	writeln("total time:           ", exited - before);

	writeln("bytes not cleaned up:", _rallocator.bytesUsed);
}

/*

void main()
{
	enum BATCH = 1000;
	enum COUNT = 100_000;

	writeln("spawning ", BATCH, " co-existent fibers on one reactor ", COUNT, " times in a row ...");

	entrypoint({
		for (auto j = 0; j < COUNT; j++)
		{
			for (auto i = 0; i < BATCH; i++)
				spawn({});

			// yield a few times to let all the others die.
			// idk how many i need but this should do lol
			for (auto h = 0; h < 10; h++) yield();
		}
	});

	writeln("created ", allocations, " objects, using ", bytesAllocd, " bytes");
}

 */
