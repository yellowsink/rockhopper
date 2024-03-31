import std.stdio;
import std.datetime : dur;

import reactor;

void main()
{
	entrypoint(&mainAsync);
}

void mainAsync()
{
	import events;
	import std.string : assumeUTF, representation;
	import core.sys.posix.unistd : pipe, close;
	import eventcore.core : eventDriver;

	int[2] fdPair;
	assert(0 == pipe(fdPair));

	auto writeEnd = eventDriver.pipes.adopt(fdPair[1]);
	auto readEnd = eventDriver.pipes.adopt(fdPair[0]);

	writeln(pipeWrite(writeEnd, "hewwo".representation));

	auto buf = new ubyte[5];
	writeln(pipeRead(readEnd, buf));
	writeln(buf.assumeUTF);

	// we close our pipes and prevent angry gc error messages about memory leaks 🔥
	// jesus we need a wrapper around FILE* like phobos does omg
	eventDriver.pipes.releaseRef(writeEnd);
	eventDriver.pipes.releaseRef(readEnd);
}
