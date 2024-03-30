import std.stdio;
import std.datetime : dur;

import reactor;

int SIGWINCH = 28; // x86, 20 on MIPS and 23 on PARISC

void main()
{
	entrypoint(&mainAsync);
}

void mainAsync()
{
	import events;

	writeln("resize your terminal pls");

	while (true)
	{
		auto status = signalTrap(SIGWINCH);
		assert(status == SignalStatus.ok);
		writeln("You resized it!");
	}
}
