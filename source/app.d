import std.stdio;
import std.datetime : dur, MonoTime;

import reactor;
import llevents;

void main()
{
	entrypoint(&mainAsync);
}


void mainAsync()
{
	import eventcore.core : eventDriver;
	import core.thread.osthread : Thread;

	shared eid = eventDriver.events.create();

	new Thread({
		Thread.sleep(dur!"msecs"(500));

		eventDriver.events.trigger(eid, true);
	}).start();

	auto before = MonoTime.currTime;

	waitThreadEvent(eid); // TODO: <-- HANGS FOREVER!
	// works as expected on a thread

	writeln("other thread triggered after ", MonoTime.currTime - before);
}
