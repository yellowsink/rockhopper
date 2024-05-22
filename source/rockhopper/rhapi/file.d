module rockhopper.rhapi.file;

import rockhopper.core.reactor;
import rockhopper.core.uda;

public import eventcore.driver : FileOpenMode;
import eventcore.driver : FileFD, OpenStatus, IOStatus;


/*
  Large parts of the File struct here are heavily based upon the File implementation in Phobos.
  Phobos is licensed under the Boost Software License:

  Boost Software License - Version 1.0 - August 17th, 2003

  Permission is hereby granted, free of charge, to any person or organization
  obtaining a copy of the software and accompanying documentation covered by
  this license (the "Software") to use, reproduce, display, distribute,
  execute, and transmit the Software, and to prepare derivative works of the
  Software, and to permit third-parties to whom the Software is furnished to
  do so, all subject to the following:

  The copyright notices in the Software and this entire statement, including
  the above license grant, this restriction and the following disclaimer,
  must be included in all copies of the Software, in whole or in part, and
  all derivative works of the Software, unless such copies or derivative
  works are solely in the form of machine-executable object code generated by
  a source language processor.

  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
  FITNESS FOR A PARTICULAR PURPOSE, TITLE AND NON-INFRINGEMENT. IN NO EVENT
  SHALL THE COPYRIGHT HOLDERS OR ANYONE DISTRIBUTING THE SOFTWARE BE LIABLE
  FOR ANY DAMAGES OR OTHER LIABILITY, WHETHER IN CONTRACT, TORT OR OTHERWISE,
  ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
  DEALINGS IN THE SOFTWARE.

*/

class FileException(S) : Exception
{
	static if (!is(S == void))
	{
		S status;

		this(S st, string msg)
		{
			status = st;
			super(msg);
		}
	}
}

alias FileIOException = FileException!IOStatus;
alias FileOpenException = FileException!OpenStatus;

// a quick note on types
// int / HANDLE  system FD or handle
// FILE* C       stdio.h streams <-- *THIS IS A RED HERRING, RESIST THE URGE TO USE THIS HERE*
// phobos file   wraps a FILE*
// FileFD        wraps an int / HANDLE
// rh File       wraps a FileFD

// note: unlike sync, this *is* copyable via refcounting
// modelled after the implementation of phobos/std/stdio.d/File
struct File
{
@safe:

	import std.traits : Parameters, ReturnType;
	import core.memory : pureMalloc, pureFree;
	import core.atomic : atomicStore, atomicLoad, atomicOp;
	import eventcore.core : eventDriver;

	import rockhopper.core.llevents : fileOpen, fileClose, fileRead, fileWrite;
	import rockhopper.rhapi.syncf : FMutex; // TODO: TMutex

	// === STORAGE ===

	// struct to keep it all close together in memory
	private struct Impl {
		FileFD fd; // null if another instance closes this file
		shared uint refCount;
		bool noAutoClose; // if true, never close automatically
		FMutex mutex;

	}
	private Impl* _impl;
	private string _name; // TODO: remove this

	// === CONSTRUCTORS ===

	this(int handle, string name, uint refs = 1, bool noAutoClose = false) nothrow
	{
		initialize(eventDriver.files.adopt(handle), name, refs, noAutoClose);
	}

	this(FileFD handle, string name, uint refs = 1, bool noAutoClose = false) @nogc nothrow
	{
		initialize(handle, name, refs, noAutoClose);
	}

	private void initialize(FileFD handle, string name, uint refs = 1, bool noAutoClose = false) @nogc nothrow @trusted
	{
		assert(!_impl);
		_impl = cast(Impl*) pureMalloc(Impl.sizeof);
		assert(_impl);


		_impl.fd = handle;
		_impl.noAutoClose = noAutoClose;
		atomicStore(_impl.refCount, refs);
		_name = name;
	}

	// i've checked, async *struct* constructors are safe!
	this(string name, FileOpenMode mode) @trusted @Async
	{
		auto fd = fileOpen(name, mode);
		check!(OpenStatus.ok)(opened.status, (s) => "open failed: " ~ s);

		initialize(fd.fd, name);
	}

	// === LIFECYCLE ===

	// +1 refcount for fresh instances
	this(this)
	{
		if (!_impl) return; // null impl, whatever
		assert(atomicLoad(_impl.refCount));
		atomicOp!"+="(_impl.refCount, 1);
	}

	~this() => detach();

	// -1 refcount & free & close
	void detach() @trusted
	{
		if (!_impl) return;
		scope(exit) _impl = null;

		if (atomicOp!"-="(_impl.refCount, 1) == 0)
		{
			scope(exit) pureFree(_impl);

			if (!_impl.noAutoClose)
				eventDriver.files.releaseRef(_impl.fd); // closes the fd synchronously
		}
	}

	// === UTILS ===

	// throws FileException!S if v != OK
	private void check(alias OK)(typeof(OK) v, string delegate(string) @safe TEM)
	{
		import std.exception : enforce;
		import std.conv : to;

		enforce(v == OK, new FileException!(typeof(OK))(v, TEM(v.to!string)));
	}

	// === FILE OPERATIONS ===

	// replaces the currently open file of this instance with a new one
	void open(string name, FileOpenMode mode) @trusted @Async
	{
		if (_impl !is null)
			detach(); // if this instance points to a file, detach

		auto opened = fileOpen(name, mode);
		// if this fails, leaves the file with no _impl attached cleanly.
		check!(OpenStatus.ok)(opened.status, (s) => "open failed: " ~ s);

		initialize(opened.fd, name);
	}

	// need to check fd because will be null if another instance closed the file.
	@property bool isOpen() const pure nothrow
		=> _impl !is null && _impl.fd;

	// if open closes, else does nothing
	void close() @trusted
	{
		if (!_impl) return;

		scope(exit)
		{
			// basically the logic from detach()
			if (atomicOp!"-="(_impl.refCount, 1) == 0)
				pureFree(_impl);
			_impl = null;
		}

		if (!_impl.fd) return; // already closed on another thread
		scope(exit) _impl.fd = typeof(_impl.fd).init; // why not

		eventDriver.files.releaseRef(_impl.fd); // close
	}

	void sync() @trusted
	{
		// TODO: Windows support
		// TODO: Darwin support
		import core.sys.posix.unistd : fsync;
		import std.exception : errnoEnforce;

		errnoEnforce(fsync(fileno) == 0);
	}

	// TODO: actual I/O apis

	@property int fileno() const @trusted
	{
		auto fd = _impl.fd.value.value;
		assert(fd < int.max);
		return cast(int) fd;
	}

	ulong rawRead(ulong oset, ubyte[] buf) @trusted @Async
	{
		_impl.mutex.lock();
		auto res = fileRead(_impl.fd, oset, buf);
		_impl.mutex.unlock();
		check!(IOStatus.ok)(res.status, (s) => "read error: " ~ s);
		return res.bytesRWd;
	}

	ulong rawWrite(ulong oset, const(ubyte)[] buf) @trusted @Async
	{
		_impl.mutex.lock();
		auto res = fileWrite(_impl.fd, oset, buf);
		_impl.mutex.unlock();
		check!(IOStatus.ok)(res.status, (s) => "write error: " ~ s);
		return res.bytesRWd;
	}
}
