module blockers;

import std.typecons : Tuple, tuple;
import taggedalgebraic : TaggedUnion;
import eventcore.driver : EventID, FileFD, PipeFD, IOMode, ProcessID, TimerID, ExitReason, IOStatus, FileOpenMode, OpenStatus;

// === BLOCKER SENDS ===

public
{
	struct BlockerFileOpen
	{
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
}

private union _FiberBlockerRaw
{
	// TODO: implement more of these
	//string nsLookup;
	//EventID ecThreadEvent;
	BlockerFileOpen fileOpen;
	BlockerFileRead fileRead;
	//Tuple!(FileFD, ulong, const(ubyte)[], IOMode) fileWrite;
	//Tuple!(PipeFD, ulong, ubyte[], IOMode) pipeRead;
	//Tuple!(PipeFD, ulong, const(ubyte)[], IOMode) pipeWrite;
	//ProcessID procWait;
	//int signalTrap;
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
		FileFD fd;
		OpenStatus status;
	}

	struct BlockerReturnFileRead
	{
		IOStatus status;
		// 0 if error
		ulong bytesRead;
	}
}

private union _BlockerReturnRaw
{
	BlockerReturnFileOpen fileOpen;
	BlockerReturnFileRead fileRead;
	Object sleep; // basically empty but pretty sure `void` will cause... issues.
}

public alias BlockerReturn = TaggedUnion!_BlockerReturnRaw;