# `rockhopper.core.suspends`

A "suspend" is a reason for a fiber to be paused by the reactor.
This module includes types that describe these.

A "suspend send" is an object describing what you want to suspend on, and a "suspend return" is an object describing
the outcome of a suspend.

These are all understood natively by the reactor, and all have user friendly wrappers in `llevents`.

This page will not describe each kind of suspend in full detail, as that is done on the `llevents` page.
It instead serves more as an API reference.

## `SuspendSend`

```d
TaggedUnion!(union
{
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
	SSDgramSend dgramSend;
	SSStreamWrite streamWrite;
	TimerID sleep;
})
```

This is a [`TaggedUnion`](https://code.dlang.org/packages/taggedalgebraic) representing any suspend send.

## `SuspendReturn`

```d
TaggedUnion!(union
{
	SRNsLookup nsLookup;
	Void threadEvent;
	SRFileOpen fileOpen;
	CloseStatus fileClose;
	SRRW rw;
	int procWait;
	SRSignalTrap signalTrap;
	SRStreamConnect streamConnect;
	SRDgramSendReceive dgramSendReceive;
	Void sleep;
})
```

This is a `TaggedUnion` representing any possible suspend return.
Note that some of these are re-used to correspond to multiple sends, especially `rw`.

## Suspend list

| Suspend          | Send            | Return             | `llevents` Wrapper | Description                                                              |
| ---------------- | --------------- | ------------------ | ------------------ | ------------------------------------------------------------------------ |
| DNS Lookup       | `nsLookup`      | `nsLookup`         | `nsLookup`         | Performs a DNS lookup on the given host and returns the resulting IPs    |
| Thread Event     | `threadEvent`   | `threadEvent`      | `waitThreadEvent`  | Waits for a thread event created on the current thread to be triggered   |
| File Open        | `fileOpen`      | `fileOpen`         | `fileOpen`         | Opens a file with the given mode                                         |
| File Close       | `fileClose`     | `fileClose`        | `fileClose`        | Closes a file descriptor                                                 |
| File Read        | `fileRead`      | `rw`               | `fileRead`         | Reads a file at a given offset into a given buffer                       |
| Pipe Read        | `pipeRead`      | `rw`               | `pipeRead`         | Reads from a pipe into a given buffer                                    |
| File Write       | `fileWrite`     | `rw`               | `fileWrite`        | Writes the buffer at the given offset to the file                        |
| Pipe Write       | `pipeWrite`     | `rw`               | `pipeWrite`        | Writes the buffer into the pipe                                          |
| Process Wait     | `procWait`      | `procWait`         | `processWait`      | Waits for a process to close                                             |
| Signal Trap      | `signalTrap`    | `signalTrap`       | `signalTrap`       | Listens for a POSIX signal (you MUST immediately `releaseRef` on the id) |
| Stream Connect   | `streamConnect` | `streamConnect`    | `streamConnect`    | Opens a TCP connection to the given socket                               |
| Stream Read      | `streamRead`    | `rw`               | `streamRead`       | Reads from a TCP stream                                                  |
| Stream Write     | `streamWrite`   | `rw`               | `streamWrite`      | Writes to a TCP stream                                                   |
| Datagram Receive | `dgramReceive`  | `dgramSendReceive` | `dgramReceive`     | Receives a datagram from a UDP socket                                    |
| Datagram Send    | `dgramSend`     | `dgramSendReceive` | `dgramSend`        | Sends a datagram to a UDP socket                                         |
| Sleep            | `sleep`         | `sleep`            | `sleep`            | Waits for a one-shot timer to fire                                       |

## `SSRead(FD)`

The family of types used for reading follow the pattern:

```d
struct SSRead(FD)
{
	FD fd; // fd type depends on resource type
	ulong offset; // only used for files but here always nonetheless
	ubyte[] buf;
	IOMode ioMode;
}
```

| Struct Name      | FD Type            |
| ---------------- | ------------------ |
| `SSFileRead`     | `FileFD`           |
| `SSPipeRead`     | `PipeFD`           |
| `SSStreamRead`   | `StreamSocketFD`   |
| `SSDgramReceive` | `DatagramSocketFD` |

## `SSWrite(FD)`

The family of types used for writing follow the pattern:

```d
struct SSWrite(FD)
{
	FD fd; // fd type depends on resource type
	ulong offset; // only used for files but here always nonetheless
	const(ubyte)[] buf;
	IOMode ioMode;
}
```

| Struct Name     | FD Type          |
| --------------- | ---------------- |
| `SSFileWrite`   | `FileFD`         |
| `SSPipeWrite`   | `PipeFD`         |
| `SSStreamWrite` | `StreamSocketFD` |

## `SSFileOpen`

```d
struct SSFileOpen
{
	string path;
	FileOpenMode mode;
}
```

## `SSStreamConnect`

```d
struct SSStreamConnect
{
	Address peerAddress;
	Address bindAddress;
}
```

## `SSDgramSend`

```d
struct SSDgramSend
{
	DatagramSocketFD fd;
	const(ubyte)[] buf;
	IOMode ioMode;
	Address targetAddress;
}
```

## `SRNsLookup`

```d
struct SRNsLookup
{
	DNSStatus status;
	RefAddress[] addresses;
}
```

## `SRFileOpen`

```d
struct SRFileOpen
{
	FileFd fd;
	OpenStatus status;
}
```

## `SRRW`

```d
struct SRRW
{
	IOStatus status;
	ulong bytesRWd;
}
```

## `SRStreamConnect`

```d
struct SRStreamConnect
{
	StreamSocketFD fd;
	ConnectStatus status;
}
```

## `SRDgramSendReceive`

```d
struct SRDgramSendReceive
{
	IOStatus status;
	ulong bytesRWd;
	RefAddress addr;
}
```

## `SRSignalTrap`

```d
struct SRSignalTrap
{
	SignalListenID slID;
	SignalStatus status;
}
```
