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

	struct SSSockConnect
	{
		import std.socket : Address;
		Address peerAddress;
		Address bindAddress;
	}

	struct SSSockListen
	{
		import std.socket : Address;
		import eventcore.driver : StreamListenOptions;

		scope Address bindAddress;
		StreamListenOptions opts;
	}

	struct SSSockSend
	{
		import std.socket : Address;

		DatagramSocketFD sock;
		const(ubyte)[] buf;
		IOMode ioMode;
		Address targetAddress;
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

	alias SSFileRead = SSRead!FileFD;
	alias SSPipeRead = SSRead!PipeFD;
	alias SSSockRead = SSRead!StreamSocketFD;
	alias SSSockReceive = SSRead!DatagramSocketFD;
	alias SSFileWrite = SSWrite!FileFD;
	alias SSPipeWrite = SSWrite!PipeFD;
	alias SSSockWrite = SSWrite!StreamSocketFD;
}


private union _SSRaw
{
	import eventcore.driver : TimerID, ProcessID, EventID, StreamListenSocketFD;
	import std.socket : Address;

	// TODO: currently, nsLookup is disabled due to all returned addresses being null
	//string nsLookup;
	EventID threadEvent;
	SSFileOpen fileOpen;
	FileFD fileClose;
	SSFileRead fileRead;
	SSPipeRead pipeRead;
	SSFileWrite fileWrite;
	SSPipeWrite pipeWrite;
	ProcessID procWait;
	int signalTrap;
	SSSockConnect sockConnect; // TODO: test
	SSSockListen sockListen; // does this call the cb many times?? // TODO: test
	SSSockRead sockRead; // can be used to wait for data if iomode.{once,all} and buf.length==0 // TODO: test
	SSSockReceive sockReceive; // TODO: test
	SSSockSend sockSend; // TODO: test
	StreamListenSocketFD sockWaitConns; // does this call the cb many times?? // TODO: test
	StreamSocketFD sockWaitData; // TODO: test
	SSSockWrite sockWrite; // wrap this in an fSynchronized! when exposed at a high level // TODO: test
	TimerID sleep;
	// TODO: directory watchers
}

public alias SuspendSend = TaggedUnion!_SSRaw;

// === RETURNS ===

public
{
	/* struct SRNsLookup
	{
		import eventcore.driver : DNSStatus, RefAddress;

		DNSStatus status;
		RefAddress[] addresses;
	} */

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

	struct SRSockConnect
	{
		import eventcore.driver : ConnectStatus;

		StreamSocketFD fd;
		ConnectStatus status;
	}

	struct SRSockSendReceive
	{
		import eventcore.driver : IOStatus, RefAddress;

		IOStatus status;
		// 0 if error
		ulong bytesRWd;
		scope RefAddress addr;
	}

	struct SRSockListen
	{
		import eventcore.driver : StreamListenSocketFD, RefAddress;

		StreamListenSocketFD listenFd;
		StreamSocketFD sockFd;
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

	//SRNsLookup nsLookup;
	Void threadEvent;
	SRFileOpen fileOpen;
	CloseStatus fileClose;
	SRRW rw;
	int procWait;
	SRSignalTrap signalTrap;
	SRSockConnect sockConnect;
	StreamListenSocketFD sockListen;
	SRSockSendReceive sockReceive;
	SRSockSendReceive sockSend;
	SRSockWaitConns sockWaitConns;
	Void sleep;
}

public alias SuspendReturn = TaggedUnion!_SRRaw;
