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
	import std.string : assumeUTF;

	// open two files in parallel, read some bytes from one, and write it into the other
	// TODO: better cross-fiber synchronization tools (tasks abstraction?)

	auto buf = new ubyte[5];
	bool readFinished = false;

	spawn({
		writeln("opening dub.json for read...");
		auto dubJson = fileOpen("dub.json", FileOpenMode.read);

		writeln("open ", dubJson.status, ", reading bytes 20-25 from dub.json...");
		auto readRes = fileRead(dubJson.fd, 20, buf);
		assert(readRes.bytesRWd == 5);
		writeln("read result: \"", buf.assumeUTF, "\", status ", readRes.status);

		readFinished = true;
	});

	spawn({
		writeln("opening test.txt (createTrunc)...");
		auto testTxt = fileOpen("test.txt", FileOpenMode.createTrunc);

		writeln("opened test.txt ", testTxt.status);

		while (!readFinished)
		{
			// wait for read to finish, only the open really works in parallel.
			writeln("waiting for read to finish before write can go ahead");
			yield();
		}

		writeln("writing to test.txt");
		auto writeRes = fileWrite(testTxt.fd, 0, buf);
		assert(writeRes.bytesRWd == 5);
		writeln("write ", writeRes.status);
	});
}
