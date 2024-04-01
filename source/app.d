import std.stdio;
import std.datetime : dur, MonoTime;

import reactor;
import events;

enum FILE_PATH = "/home/sink/Downloads/Pokemon Brilliant Diamond + Pokemon Shining Pearl [NSPs]/Pokemon Brilliant Diamond (NSP)(eShop).rar";

// read 50mb chunks 100 mb apart until run out
// also do the same but offset by 50mb

void bench(alias F, string l)()
{
	//auto dc = File("/proc/sys/vm/drop_caches", "w");

	auto time = dur!"msecs"(0);
	for (auto i = 0; i < 5; i++)
	{
		//dc.write("3");
		//dc.flush();
		benchSync(); // refresh cache

		auto before = MonoTime.currTime;
		F();
		time += (MonoTime.currTime - before);
	}
	writeln(l, ": ", time);
}

void main()
{
	writeln("sync = read the file in a loop with `File.rawRead`");
	writeln("threads = that but on threads, `File.seek`ing as necessary");
	writeln("fibers = rockhopper.events `fileRead()` in a loop");
	writeln("alternating = each thread 'leapfrogs' the other reading alternaing chunks");
	writeln("sequential = each thread reads the first/second half of the file contiguously");
	writeln("each is reading a 4.6GB file in 50MB chunks, 5 times in a row.");
	writeln("linux cache is refreshed by a full reread between each run");
	//writeln("3 is written to /proc/sys/vm/drop_caches between each run");

	bench!(benchSync,          "sync                     ");
	bench!(benchTwoThreadsAlt, "two threads, alternating ");
	bench!(benchTwoThreadsSeq, "two threads, sequential  ");
	bench!(benchOneFiber,      "one rockhopper fiber     ");
	bench!(benchTwoFibersAlt,  "two fibers, alternating  ");
	bench!(benchTwoFibersSeq,  "two fibers, sequential   ");
}

ulong getHalfwayQuantized(File f)
{
	ulong half = f.size / 2;
	ulong x = 0;
	while (x < half) x += 50_000_000;
	return x;
}


void benchSync()
{
	auto f = File(FILE_PATH);

	auto buf = new ubyte[50_000_000];

	for (ulong i = 0; ; i += 50_000_000)
	{
		auto slice = f.rawRead(buf);
		if (slice.length != buf.length) break;
	}
}

void benchTwoThreadsAlt()
{
	import core.thread.osthread : Thread;

	auto t1 = new Thread({
		auto f = File(FILE_PATH);

		auto buf = new ubyte[50_000_000];

		for (ulong i = 0; ; i += 100_000_000)
		{
			// relative seeks only because
			// the file is too big for 32 bit ints
			f.seek(50_000_000, 1);
			auto writtenSlice = f.rawRead(buf);
			if (writtenSlice.length < buf.length) break;
		}
	}).start();

	auto t2 = new Thread({
		auto f = File(FILE_PATH);

		auto buf = new ubyte[50_000_000];

		for (ulong i = 50_000_000; ; i += 100_000_000)
		{
			f.seek(50_000_000, 1);
			auto writtenSlice = f.rawRead(buf);
			if (writtenSlice.length < buf.length) break;
		}
	}).start();

	t1.join();
	t2.join();
}

void benchTwoThreadsSeq()
{
	import core.thread.osthread : Thread;

	auto t1 = new Thread({
		auto f = File(FILE_PATH);
		auto halfWayPoint = getHalfwayQuantized(f);

		auto buf = new ubyte[50_000_000];

		for (ulong i = 0; i < halfWayPoint; i += 100_000_000)
		{
			// relative seeks only because
			// the file is too big for 32 bit ints
			f.seek(50_000_000, 1);
			f.rawRead(buf);
		}
	}).start();

	auto t2 = new Thread({
		auto f = File(FILE_PATH);
		auto halfWayPoint = getHalfwayQuantized(f);

		auto buf = new ubyte[50_000_000];

		for (ulong i = halfWayPoint;; i += 100_000_000)
		{
			f.seek(50_000_000, 1);
			auto writtenSlice = f.rawRead(buf);
			if (writtenSlice.length < buf.length)
				break;
		}
	}).start();

	t1.join();
	t2.join();
}

void benchOneFiber()
{
	entrypoint({
		auto f = fileOpen(FILE_PATH, FileOpenMode.read);

		auto buf = new ubyte[50_000_000];

		for (ulong i = 0;; i += 100_000_000)
		{
			auto res = fileRead(f.fd, i, buf);
			if (res.status != IOStatus.ok)
				break;
		}
	});
}

void benchTwoFibersAlt()
{
	entrypoint({
		spawn({
			auto f = fileOpen(FILE_PATH, FileOpenMode.read);

			auto buf = new ubyte[50_000_000];

			for (ulong i = 0;; i += 100_000_000)
			{
				auto res = fileRead(f.fd, i, buf);
				if (res.status != IOStatus.ok)
					break;
			}
		});

		spawn({
			auto f = fileOpen(FILE_PATH, FileOpenMode.read);

			auto buf = new ubyte[50_000_000];

			for (ulong i = 50_000_000;; i += 100_000_000)
			{
				auto res = fileRead(f.fd, i, buf);
				if (res.status != IOStatus.ok)
					break;
			}
		});
	});
}

void benchTwoFibersSeq()
{
	auto halfWayPoint = getHalfwayQuantized(File(FILE_PATH));

	entrypoint({
		spawn({
			auto f = fileOpen(FILE_PATH, FileOpenMode.read);

			auto buf = new ubyte[50_000_000];

			for (ulong i = 0; i < halfWayPoint; i += 100_000_000)
			{
				fileRead(f.fd, i, buf);
			}
		});

		spawn({
			auto f = fileOpen(FILE_PATH, FileOpenMode.read);

			auto buf = new ubyte[50_000_000];

			for (ulong i = halfWayPoint;; i += 100_000_000)
			{
				auto res = fileRead(f.fd, i, buf);
				if (res.status != IOStatus.ok)
					break;
			}
		});
	});
}
