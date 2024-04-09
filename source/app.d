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
	import eventcore.core : eventDriver, ProcessRedirect, ProcessStderrRedirect, ProcessConfig, ProcessStdinFile, ProcessStdoutFile, ProcessStderrFile;

	auto p = eventDriver.processes.spawn(
		["/bin/pacman", "-Q"],
		ProcessStdinFile(ProcessRedirect.none),
		ProcessStdoutFile(ProcessRedirect.pipe),
		ProcessStderrFile(ProcessStderrRedirect.toStdout),
		null, ProcessConfig.none, null);

	writeln("spawned process, waiting: ", p.pid.value);

	auto tBefore = MonoTime.currTime;

	while (1) yield();

	//processWait(p.pid);

	writeln("process exited, took ", MonoTime.currTime - tBefore);
}
