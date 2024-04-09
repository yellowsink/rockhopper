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

	import std.process : spawnProcess, pipe, wait;

	auto p = pipe();

	auto pid = spawnProcess(["yay", "-Q"], std.stdio.stdin, p.writeEnd, p.writeEnd);

	auto adopted = eventDriver.processes.adopt(pid.processID);

	writeln("spawned process, waiting: ", pid.osHandle);

	auto tBefore = MonoTime.currTime;

	auto res = processWait(adopted);

	writeln("process exited with code ", res, ", took ", MonoTime.currTime - tBefore);

	// read all output
	import std.algorithm : count;
	auto adoptedPipe = eventDriver.pipes.adopt(p.readEnd.fileno);
	auto buf = new ubyte[10_000_000]; // lol
	pipeRead(adoptedPipe, buf);
	auto lines = buf.count(cast(ubyte) '\n');

	p.close();
	eventDriver.pipes.releaseRef(adoptedPipe); // must happpen AFTER close, just to make eventcore happy.

	writeln("output had ", lines, " lines");
}
