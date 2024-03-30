module blockers;

import std.typecons : Tuple, tuple;
import taggedalgebraic : TaggedUnion;
import eventcore.driver : /* EventID, */ FileFD, /* PipeFD, */ IOMode;

// === BLOCKER SENDS ===

public
{
	struct BlockerFileOpen
	{
		import eventcore.driver : FileOpenMode;

		string path;
		FileOpenMode mode;
	}

	struct BlockerFileRead
	{
		FileFD fd;
		ulong offset;
		ubyte[] buf;
		IOMode ioMode;
	}

	struct BlockerFileWrite
	{
		FileFD fd;
		ulong offset;
		const(ubyte)[] buf;
		IOMode ioMode;
	}
}

private union _FiberBlockerRaw
{
	import eventcore.driver : TimerID/* , ProcessID */;

	// TODO: implement more of these
	//string nsLookup;
	//EventID ecThreadEvent;
	BlockerFileOpen fileOpen;
	BlockerFileRead fileRead;
	BlockerFileWrite fileWrite;
	//Tuple!(PipeFD, ulong, ubyte[], IOMode) pipeRead;
	//Tuple!(PipeFD, ulong, const(ubyte)[], IOMode) pipeWrite;
	//ProcessID procWait;
	int signalTrap;
	// TODO: sockets
	TimerID sleep;
	// TODO: directory watchers
}

public alias FiberBlocker = TaggedUnion!_FiberBlockerRaw;

// === BLOCKER RETURNS ===

public
{
	struct BlockerReturnFileOpen
	{
		import eventcore.driver : OpenStatus;

		FileFD fd;
		OpenStatus status;
	}

	struct BlockerReturnFileRW
	{
		import eventcore.driver : IOStatus;

		IOStatus status;
		// 0 if error
		ulong bytesRWd;
	}

	struct BlockerReturnSignalTrap
	{
		import eventcore.driver : SignalListenID, SignalStatus;

		SignalListenID slID;
		SignalStatus status;
	}
}

private union _BlockerReturnRaw
{
	BlockerReturnFileOpen fileOpen;
	BlockerReturnFileRW fileRW;
	BlockerReturnSignalTrap signalTrap;
	Object sleep; // basically empty but pretty sure `void` will cause... issues.
}

public alias BlockerReturn = TaggedUnion!_BlockerReturnRaw;
