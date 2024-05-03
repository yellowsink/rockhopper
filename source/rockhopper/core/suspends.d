// `suspends` contains the types that are used by the reactor API to represent blocking tasks and their results.
// both this and llawait() can be considered implementation details of llevents, but are exposed nonetheless.
// a "suspend" refers to a reason for your fiber to be on hold by the reactor
// not to be confused with a "suspend send", an object representing a suspend, sent to the reactor
// and a "suspend return" is sent back to the fiber from the reactor once it has been fulfilled.
module rockhopper.core.suspends;

import std.typecons : Tuple, tuple;
import taggedalgebraic : TaggedUnion, Void;
import eventcore.driver : FileFD, PipeFD, IOMode, StreamSocketFD, DatagramSocketFD;

// === SENDS ===

private
{
	struct SSRead(FD)
	{
		FD fd;
		ulong offset;
		ubyte[] buf;
		IOMode ioMode;
	}

	struct SSWrite(FD)
	{
		FD fd;
		ulong offset; // only used for files, ignored for pipes
		const(ubyte)[] buf;
		IOMode ioMode;
	}
}

public
{
	struct SSFileOpen
	{
		import eventcore.driver : FileOpenMode;

		string path;
		FileOpenMode mode;
	}

	struct SSStreamConnect
	{
		import std.socket : Address;

		Address peerAddress;
		Address bindAddress;
	}

	struct SSSockSend
	{
		import std.socket : Address;

		DatagramSocketFD sock;
		const(ubyte)[] buf;
		IOMode ioMode;
		Address targetAddress;
	}

	alias SSFileRead = SSRead!FileFD;
	alias SSPipeRead = SSRead!PipeFD;
	alias SSStreamRead = SSRead!StreamSocketFD;
	alias SSDgramReceive = SSRead!DatagramSocketFD;
	alias SSFileWrite = SSWrite!FileFD;
	alias SSPipeWrite = SSWrite!PipeFD;
	alias SSSockWrite = SSWrite!StreamSocketFD;
}


private union _SSRaw
{
	import eventcore.driver : TimerID, ProcessID, EventID, StreamListenSocketFD;
	import std.socket : Address;

	string nsLookup;
	EventID threadEvent;
	SSFileOpen fileOpen;
	FileFD fileClose;
	SSFileRead fileRead;
	SSPipeRead pipeRead;
	SSFileWrite fileWrite;
	SSPipeWrite pipeWrite;
	ProcessID procWait;
	int signalTrap;
	SSStreamConnect streamConnect;
	SSStreamRead streamRead;
	SSDgramReceive dgramReceive;
	SSSockSend sockSend; // TODO: test
	/* StreamListenSocketFD sockWaitConns; // TODO: cannot be awaited - remove this from suspends entirely and handle in llevents?
	                                    // TODO: test */
	StreamSocketFD sockWaitData; // TODO: test
	SSSockWrite sockWrite; // TODO: wrap this in an fSynchronized! when exposed at a high level // TODO: test
	TimerID sleep;
	// TODO: directory watchers
}

public alias SuspendSend = TaggedUnion!_SSRaw;

// === RETURNS ===

public
{
	struct SRNsLookup
	{
		import eventcore.driver : DNSStatus, RefAddress;

		DNSStatus status;
		RefAddress[] addresses;
	}

	struct SRFileOpen
	{
		import eventcore.driver : OpenStatus;

		FileFD fd;
		OpenStatus status;
	}

	struct SRRW
	{
		import eventcore.driver : IOStatus;

		IOStatus status;
		// 0 if error
		ulong bytesRWd;
	}

	struct SRStreamConnect
	{
		import eventcore.driver : ConnectStatus;

		StreamSocketFD fd;
		ConnectStatus status;
	}

	struct SRDgramSendReceive
	{
		import eventcore.driver : IOStatus, RefAddress;

		IOStatus status;
		// 0 if error
		ulong bytesRWd;
		RefAddress addr;
	}

	struct SRSockWaitConns
	{
		import eventcore.driver : RefAddress;

		StreamSocketFD fd;
		RefAddress addr;
	}

	struct SRSignalTrap
	{
		import eventcore.driver : SignalListenID, SignalStatus;

		SignalListenID slID;
		SignalStatus status;
	}
}

private union _SRRaw
{
	import eventcore.driver : CloseStatus;

	SRNsLookup nsLookup;
	Void threadEvent;
	SRFileOpen fileOpen;
	CloseStatus fileClose;
	SRRW rw;
	int procWait;
	SRSignalTrap signalTrap;
	SRStreamConnect streamConnect;
	SRDgramSendReceive dgramReceive;
	SRDgramSendReceive sockSend;
	SRSockWaitConns sockWaitConns;
	Void sleep;
}

public alias SuspendReturn = TaggedUnion!_SRRaw;
