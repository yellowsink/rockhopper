import std.stdio;
import std.datetime : dur, MonoTime;

import reactor;
import llevents;
import syncf;

void main()
{
	entrypoint(&mainAsync);
}


void mainAsync()
{
	FGuardedResult!uint res;

	spawn({
		sleep(dur!"msecs"(500));

		res.set(9);
	});

	writeln(res.get); // .get waits for a value to be assigned
}
