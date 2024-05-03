# `rockhopper.core.suspends`

A "suspend" is a reason for a fiber to be paused by the reactor.
This module includes types that describe these.

A "suspend send" is an object describing what you want to suspend on, and a "suspend return" is an object describing
the outcome of a suspend.

These are all understood natively by the reactor, and all have user friendly wrappers in `llevents`.

This page will not describe each kind of suspend in full detail, as that is done on the `llevents` page.

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

## DNS lookup

```d
// send
string nsLookup

// return
SRNsLookup nsLookup

struct SRNsLookup { DNSStatus status; RefAddress[] addresses; }
```

`llevents` wrapper: `nsLookup`

Performs a DNS lookup on the given host and returns the resulting IPs.

## Thread Events

```d
// send
EventID threadEvent

// return
Void threadEvent
```

`llevents` wrapper: `waitThreadEvent`

Waits for a thread event created on the current thread.

## File Open

## File Close

## File Read

## Pipe Read

## File Write

## Pipe Write

## Process Wait

## Signal Trap

## Stream Connect

## Stream Read

## Stream Write

## Datagram Receive

## Datagram Send

## Sleep
