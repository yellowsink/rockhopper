module blockers;

import std.typecons : Tuple, tuple;
import taggedalgebraic : TaggedUnion;
import eventcore.driver : FileFD, PipeFD, IOMode;

// === BLOCKER SENDS ===

private
{
	struct BlockerRead(FD)
	{
		FD fd;
		ulong offset;
		ubyte[] buf;
		IOMode ioMode;
	}

	struct BlockerWrite(FD)
	{
		FD fd;
		ulong offset;
		const(ubyte)[] buf;
		IOMode ioMode;
	}
}

public
{
	struct BlockerFileOpen
	{
		import eventcore.driver : FileOpenMode;

		string path;
		FileOpenMode mode;
	}

	alias BlockerFileRead = BlockerRead!FileFD;
	//alias BlockerPipeRead = BlockerRead!PipeFD;
	alias BlockerFileWrite = BlockerWrite!FileFD;
	//alias BlockerPipeWrite = BlockerWrite!PipeFD;
}

// TODO: test the following
// - pipe read
// - pipe write
// - spawn
// - wait

private union _FiberBlockerRaw
{
	import eventcore.driver : TimerID/* , ProcessID */;

	// TODO: currently, nsLookup is disabled due to all returned addresses being null
	//string nsLookup;
	// TODO: eventcore thread events
	BlockerFileOpen fileOpen;
	FileFD fileClose;
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
	/* struct BlockerReturnNsLookup
	{
		import eventcore.driver : DNSStatus, RefAddress;

		DNSStatus status;
		RefAddress[] addresses;
	} */

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
	import eventcore.driver : CloseStatus;

	//BlockerReturnNsLookup nsLookup;
	BlockerReturnFileOpen fileOpen;
	CloseStatus fileClose;
	BlockerReturnFileRW fileRW;
	BlockerReturnSignalTrap signalTrap;
	Object sleep; // basically empty but pretty sure `void` will cause... issues.
}

public alias BlockerReturn = TaggedUnion!_BlockerReturnRaw;
