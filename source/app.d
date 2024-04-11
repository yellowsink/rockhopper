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

	auto mainThreadDriver = cast(shared) eventDriver;

	auto eid = eventDriver.events.create();

	new Thread({
		Thread.sleep(dur!"msecs"(500));

		mainThreadDriver.events.trigger(eid, true);
	}).start();

	auto before = MonoTime.currTime;

	waitThreadEvent(eid);

	writeln("other thread triggered after ", MonoTime.currTime - before);
}
