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

	auto opened = fileOpen("dub.json", FileOpenMode.read);

	fileClose(opened.fd);
}
