# `rockhopper.core.llevents`

`llevents` (low level events) provides a series of functions (and one struct) to expose all the capabilities of
Rockhopper, in the simplest form possible.
It is relatively easy to use, but should still be used with caution.

This page provides detailed documentation on how to use each of the possible suspends.

## Important note

Any APIs marked as "singular" may only have ONE call in flight at once per resource.
For example: if I write to a file, nobody else may write to that file until I've finished.

`llevents` does not enforce this for you, but you should have measures in place to prevent it.
(hint: `rhapi.sync.fSynchronized`)

This is per-resource (generally the one that has a file descriptor), not globally.

## `nsLookup`

```d
SRNsLookup nsLookup(string) [ASYNC]
```

`nsLookup` takes a domain name in string form (e.g. "google.com", "yellows.ink"), and performs a DNS lookup on it.
You will be given back an array of addresses, which is likely to contain some duplicates.

The results include both `A` and `AAAA` fields.

[corresponding eventcore documentation](https://vibed.org/api/eventcore.driver/EventDriverDNS).

### Example

```d
auto res = nsLookup("google.com");
assert(res.status == DNSStatus.ok);
writeln(res.addresses);
```

## `waitThreadEvent`

```d
void waitThreadEvent(EventID) [ASYNC]
```

Given a thread event (created with `eventDriver.events.create`), wait for it to be triggered.
It MUST have been created on the current thread.

You can trigger this event from any thread by casting `eventDriver` to `shared`, then calling its `.events.trigger()`.

[corresponding eventcore documentation](https://vibed.org/api/eventcore.driver/EventDriverEvents)

### Example

```d
shared sdriver = eventDriver;
auto ev = eventDriver.events.create();

new Thread({
	Thread.sleep(dur!"msecs"(500));
	writeln("1!");
	sdriver.events.trigger(ev);
}).start();

waitThreadEvent(ev);
writeln("2!");
```

## `fileOpen`

```d
SRFileOpen fileOpen(string, FileOpenMode) [ASYNC]
```

Opens a file descriptor from its path and a given mode.

You must eventually pass this to either `fileClose` or `eventDriver.files.releaseRef`.

[corresponding eventcore documentation](https://vibed.org/api/eventcore.driver/EventDriverFiles.open)

## `fileClose`

```d
CloseStatus fileClose(FileFD) [ASYNC]
```

Closes a file descriptor.
Technically this is not actually asynchronous, but does behave like it for forwards compatibility.

[corresponding eventcore documentation](https://vibed.org/api/eventcore.driver/EventDriverFiles.close)

## `fileRead`

```d
SRRW fileRead(FileFD, ulong oset, ubyte[], IOMode = IOMode.once) [ASYNC] [SINGULAR]
```

Reads bytes from the file, starting at the given byte offset, into the buffer.
If you try to read past the end of the file, `bytesRWd` will be zero and an error will be returned.

Only a SINGLE read operation on each file is allowed at once.
One must return before the next can start.
This is not enforced

[corresponding eventcore documentation](https://vibed.org/api/eventcore.driver/EventDriverFiles.read)

### Example

```d
auto opened = fileOpen("data.txt", FileOpenMode.read);

// read bytes 128-192
ubyte[64] buffer;
auto res = fileRead(opened.fd, 128, buffer);
assert(res.bytesRWd == 64);

fileClose(opened.fd);

import std.string : assumeUTF;
writeln(assumeUTF(buffer));
```

## `pipeRead`

```d
SRRW pipeRead(PipeFD, ubyte[], IOMode = IOMode.once) [ASYNC] [SINGULAR]
```

Reads bytes from the pipe into the buffer.

[corresponding eventcore documentation](https://vibed.org/api/eventcore.driver/EventDriverPipes.read)

### Example

```d
import std.process : pipe;
import std.string : assumeUTF;

auto p = pipe();

p.writeEnd.writeln("test");
p.writeEnd.flush();

auto fd = eventDriver.pipes.adopt(p.readEnd.fileno);

ubyte[64] buffer;
auto res = pipeRead(fd, buffer);

assert(buffer[0 .. res.bytesRWd].assumeUTF == "test\n");

p.close();
eventDriver.pipes.releaseRef(fd);
```

## `fileWrite`

```d
SRRW fileWrite(FileFD, ulong oset, const(ubyte)[], IOMode = IOMode.once) [ASYNC] [SINGULAR]
```

Writes asynchronously to a file.

If the mode of the opened file is not `append`, and the offset is beyond the end of the file,
the buffer will be written onto the end of the file, not padded out to be written at the supplied offset - e.g.
writing at "offset 999" to a 50 byte file will start writing at byte 51.

If the mode of the opened file is `append`, the offset is ignored, and writes always append onto the end of the file.

If the mode of the opened file is `read`, this call fails.

[corresponding eventcore documentation](https://vibed.org/api/eventcore.driver/EventDriverFiles.write)

## `pipeWrite`

```d
SRRW pipeWrite(PipeFD, const(ubyte)[], IOMode = IOMode.once) [ASYNC] [SINGULAR]
```

Writes a buffer to a pipe.

[corresponding eventcore documentation](https://vibed.org/api/eventcore.driver/EventDriverPipes.write)

## `processWait`

```d
int processWait(ProcessID) [ASYNC]
```

Given a process ID, waits for it to exit, and returns the exit code.

[corresponding eventcore documentation](https://vibed.org/api/eventcore.driver/EventDriverProcesses.wait)

### Example

```d
import std.process : spawnProcess;

auto pid = spawnProcess(["ls", "-la"]);

auto adopted = eventDriver.processes.adopt(pid.processID);

writeln("exited with code: ", processWait(adopted));
```

## `signalTrap`

```d
SignalStatus signalTrap(int) [ASYNC]
```

Overrides default event handlers for the relevant signal, and waits for the specified signal to arrive.

The default handler will be re-enabled once this returns.
Note that this behaviour subtly differs from that of using the suspend directly with the reactor.

[corresponding eventcore documentation](https://vibed.org/api/eventcore.driver/EventDriverSignals.listen)

### Example

```d
spawn({ // in most cases, likely do this in the background
	signalTrap(SIGINT);
	writeln("sigint received! do some cleanup!");
});
```

## `sleep`

```d
void sleep(Duration) [ASYNC]
```

Sleeps your thread for the given duration.
Likely to be the first function you'll try if you mess around. :p

Note that this is also subtly different to the behaviour of directly using the suspend with the reactor,
which will expect you to create a timer on your own.

[corresponding eventcore documentation](https://vibed.org/api/eventcore.driver/EventDriverTimers)

### Example

```d
import std.datetime : dur;

sleep(dur!"msecs"(500));
```

## `streamConnect`

```d
SRStreamConnect streamConnect(Address peer, Address bind) [ASYNC]
```

Initiates a TCP connection to `peer`, expecting a reply on `bind`.
`peer` generally must specify a port, but `bind` need not.

[corresponding eventcore documentation](https://vibed.org/api/eventcore.driver/EventDriverSockets.connectStream)

### Example

```d
import std.socket : parseAddress;

auto socket = streamConnect(parseAddress("192.168.1.250", 80), parseAddress("0.0.0.0"));
```

## `StreamListen`

```d
struct StreamListen
{
	Address addr;
	StreamListenOptions opts;
	Nullable!StreamListenSocketFD fd;
	Tuple(StreamSocketFD, RefAddress)[] sockets;

	void registerListen()
	void registerWaitConns()
	void cleanup()

	Tuple!(StreamSocketFD, RefAddress) wait() [ASYNC]
}
```

This struct wraps waiting for incoming TCP connections on a given address.

- First, allocate an instance of the struct, then you must set `addr` to the address you wish to bind on.
  It should have a port, and you must be capable of binding to it.
  If you want stream listening options other than the defaults, also set those.
- Then call `registerListen`. This will set things up and begin listening.
- You can call `wait` to asynchronously wait for an incoming TCP connection.
- When you're finished, `cleanup` will stop listening.

You shouldn't access `sockets` manually.

If you already have a stream listen fd (somehow?) and wish to simply start listening on that, instead of binding a new
address, you can instead, set `fd` to that value yourself, then call `registerWaitConns` instead.
`wait` and `cleanup` then act as expected.

[corresponding eventcore documentation (listen)](https://vibed.org/api/eventcore.driver/EventDriverSockets.listenStream)
[(and wait conns)](https://vibed.org/api/eventcore.driver/EventDriverSockets.waitForConnections)

### Example

```d
import std.socket : parseAddress;
import std.string : representation; // string to bytes

StreamListen listener;
listener.addr = parseAddress("::1", 8080);
listener.registerListen();

// say hi to 3 people who connect to us
for (auto i = 0; i < 3; i++)
{
	auto stream = listener.wait();

	spawn({
		streamWrite(stream[0], representation("hey there!"));
		eventDriver.sockets.releaseRef(stream[0]);
	});
}

listener.cleanup();
```

## `streamRead`

```d
SRRW streamRead(StreamSocketFD, ubyte[], IOMode = IOMode.once) [ASYNC] [SINGULAR]
```

Reads as much as possible from a TCP stream into a buffer, returning the amount read.

[corresponding eventcore documentation](https://vibed.org/api/eventcore.driver/EventDriverSockets.read)

## `streamWaitForData`

```d
IOStatus streamWaitForData(StreamSocketFD) [ASYNC] [SINGULAR]
```

Waits until data is ready, without actually reading it.
Note that the status will not necessarily reflect a passive connection close, reading data is necessary to check that.

[corresponding eventcore documentation](https://vibed.org/api/eventcore.driver/EventDriverSockets.read)

## `streamWrite`

```d
SRRW streamWrite(StreamSocketFD, const(ubyte)[], IOMode = IOMode.once) [ASYNC] [SINGULAR]
```

Writes a buffer to a TCP stream.

[corresponding eventcore documentation](https://vibed.org/api/eventcore.driver/EventDriverSockets.write)

## `dgramReceive`

```d
SDRgramSendReceive dgramReceive(DatagramSocketFD, ubyte[], IOMode = IOMode.once) [ASYNC]
```

Receives a single UDP datagram from a listening socket.
The address of the sender is provided along with the data.

[corresponding eventcore documentation](https://vibed.org/api/eventcore.driver/EventDriverSockets.receive)

### Example

```d
import std.socket : parseAddress;

auto socket = eventDriver.sockets.createDatagramSocket(parseAddress("127.0.0.1", 8080), null);

ubyte[64] buf;
auto status = dgramReceive(socket, buf);

eventDriver.sockets.releaseRef(socket);
```

## `dgramSend`

```d
SRDgramSendReceive dgranSend(DatagramSocketFD, const(ubyte)[], Address, IOMode = IOMode.once) [ASYNC]
```

Writes the buffer to the given UDP socket, to the given address.
No status reporting, this is UDP after all ;)

The returned address is always `null`.

[corresponding eventcore documentation](https://vibed.org/api/eventcore.driver/EventDriverSockets.send)

### Example

```d
import std.socket : parseAddress;
import std.string : representation;

auto socket = eventDriver.sockets.createDatagramSocket(parseAddress("127.0.0.1", 8080), null);

ubyte[64] buf;
auto statusr = dgramReceive(socket, buf);

// reply!
auto statuss = dgramSend(socket, representation("oh hey there!"), statusr.addr);

eventDriver.sockets.releaseRef(socket);
```
