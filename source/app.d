import std.stdio;
import std.datetime : dur, MonoTime;

/* import core.blockers;
import core.llevents;
import core.reactor; */
import core;
import sync;
import task;

import eventcore.core : eventDriver;

import core.thread.osthread : Thread;

void main()
{
	entrypoint({
		auto vtask = tSpawn({
			writeln("task says hi");
			sleep(dur!"msecs"(500));
		}).then({
			writeln("async continuation!");
		});

		auto itask = tSpawn({
			writeln("new task here");
			return 5;
		}).then((int v) => v > 6); // continuations can modify the value

		vtask.waitRes();

		writeln(itask.waitRes());
	});
}
