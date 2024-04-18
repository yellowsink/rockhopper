// `blockers` contains the types that are used by the reactor API to represent blocking tasks and their results
module blockers;

import std.typecons : Tuple, tuple;
import taggedalgebraic : TaggedUnion, Void;
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
		ulong offset; // only used for files, ignored for pipes
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
	alias BlockerPipeRead = BlockerRead!PipeFD;
	alias BlockerFileWrite = BlockerWrite!FileFD;
	alias BlockerPipeWrite = BlockerWrite!PipeFD;
}


private union _FiberBlockerRaw
{
	import eventcore.driver : TimerID, ProcessID, EventID;

  struct TODO {}

	// TODO: currently, nsLookup is disabled due to all returned addresses being null
	//string nsLookup;
	EventID threadEvent;
	BlockerFileOpen fileOpen;
	FileFD fileClose;
	BlockerFileRead fileRead;
	BlockerPipeRead pipeRead;
	BlockerFileWrite fileWrite;
	BlockerPipeWrite pipeWrite;
	ProcessID procWait;
	int signalTrap;
	/* TODO sockConnect; // TODO: sockets
	TODO sockListenWithoutOpts;
	TODO sockListenWithOptions;
	TODO sockRead;
	TODO sockReceive;
	TODO sockSend;
	TODO sockWaitConns;
	TODO sockWaitData;
	TODO sockWrite; */
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

	struct BlockerReturnRW
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
	Void threadEvent;
	BlockerReturnFileOpen fileOpen;
	CloseStatus fileClose;
	BlockerReturnRW rw;
	int procWait;
	BlockerReturnSignalTrap signalTrap;
	Void sleep;
}

public alias BlockerReturn = TaggedUnion!_BlockerReturnRaw;
