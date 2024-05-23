module rockhopper.rhapi.file;

import rockhopper.core.reactor;
import rockhopper.core.uda;

public import eventcore.driver : FileOpenMode;
import eventcore.driver : FileFD, PipeFD, OpenStatus, IOStatus;

import std.traits : isInstanceOf;


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

// throws FileException!S if v != OK
private void check(alias OK, alias TEM)(typeof(OK) v)
{
	import std.exception : enforce;
	import std.conv : to;

	enforce(v == OK, new FileException!(typeof(OK))(v, TEM(v.to!string)));
}

// a quick note on types
// int / HANDLE  system FD or handle
// FILE* C       stdio.h streams <-- *THIS IS A RED HERRING, RESIST THE URGE TO USE THIS HERE*
// phobos file   wraps a FILE*
// FileFD        wraps an int / HANDLE
// rh File       wraps a FileFD

// copyable via refcounting, auto closes on last detach
// modelled after the implementation of phobos/std/stdio.d/File
// if pipe, then reads and writes will not accept offsets etc. use the appropriate one for your FD type
private struct Handle(bool IS_PIPE = false, bool READABLE = true, bool WRITEABLE = true)
{
	import std.meta : AliasSeq;
	import core.memory : pureMalloc, pureFree;
	import core.atomic : atomicStore, atomicLoad, atomicOp;
	import eventcore.core : eventDriver;

	import rockhopper.core.llevents : fileOpen, fileClose, fileRead, fileWrite, pipeRead, pipeWrite;
	import rockhopper.rhapi.syncf : FMutex; // TODO: TMutex

	public enum bool isPipe = IS_PIPE;
	public enum bool isReadable = READABLE;
	public enum bool isWriteable = WRITEABLE;

	// make it easy to refer to the necessary driver
	static if(IS_PIPE)
		private auto driverfp = () => eventDriver.pipes;
	else
		private auto driverfp = () => eventDriver.files;

	static if (IS_PIPE)
		private alias FD = PipeFD;
	else
		private alias FD = FileFD;

	// === STORAGE ===

	// struct to keep it all close together in memory
	private struct Impl {
		FD fd; // null if another instance closes this file
		shared uint refCount;
		bool noAutoClose; // if true, never close automatically
		FMutex mutex;
	}
	private Impl* _impl;

	// === CONSTRUCTORS ===

	this(int handle, bool noAutoClose = true, uint refs = 1) nothrow
	{
		initialize(driverfp().adopt(handle), noAutoClose, refs);
	}

	this(FD handle, bool noAutoClose = true, uint refs = 1) @nogc nothrow
	{
		initialize(handle, noAutoClose, refs);
	}

	private void initialize(FD handle, bool noAutoClose = false, uint refs = 1) @nogc nothrow
	{
		assert(!_impl);
		_impl = cast(Impl*) pureMalloc(Impl.sizeof);
		*_impl = Impl.init; // overwrite uninitialized memory from malloc!
		assert(_impl);


		_impl.fd = handle;
		_impl.noAutoClose = noAutoClose;
		atomicStore(_impl.refCount, refs);
	}

	// i've checked, async *struct* constructors are safe!
	static if (!IS_PIPE)
	this(string name, FileOpenMode mode) @Async
	{
		auto fd = fileOpen(name, mode);
		check!(OpenStatus.ok, (s) => "open failed: " ~ s)(fd.status);

		initialize(fd.fd);
	}

	// copy constructors between pipes of different types
	static if (IS_PIPE)
	{
		this(P)(scope P rhs)
		if (
			// pipew and piper -> pipea
			(WRITEABLE && READABLE && (is(P == Handle!(true, true, false)) || is(P == Handle!(true, false, true))))
			// pipea -> pipew
			|| (WRITEABLE && !READABLE && is(P == Handle!true))
			// pipea -> piper
			|| (!WRITEABLE && READABLE && is(P == Handle!true))
		)
		{
			if (!rhs._impl) return;
			assert(atomicLoad(rhs._impl.refCount));
			atomicOp!"+="(rhs._impl.refCount, 1); // add a ref
			_impl = cast(Impl*) rhs._impl; // duplicate the impl pointer
		}
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
	void detach()
	{
		if (!_impl) return;
		scope(exit) _impl = null;

		if (atomicOp!"-="(_impl.refCount, 1) == 0)
		{
			scope(exit) pureFree(_impl);

			if (!_impl.noAutoClose)
				driverfp().releaseRef(_impl.fd); // closes the fd synchronously
		}
	}

	// === INTERNAL UTILS ===

	private T withLock(T)(T delegate() f)
	{
		_impl.mutex.lock();
		scope(exit) _impl.mutex.unlock();
		return f();
	}

	// === FILE OPERATIONS ===

	// replaces the currently open file of this instance with a new one
	static if (!IS_PIPE)
	void open(string name, FileOpenMode mode) @Async
	{
		detach(); // if this instance points to a file, detach

		auto opened = fileOpen(name, mode);
		// if this fails, leaves the file with no _impl attached cleanly.
		check!(OpenStatus.ok, (s) => "open failed: " ~ s)(opened.status);

		initialize(opened.fd);
	}

	// need to check fd because will be null if another instance closed the file.
	@property bool isOpen() const pure nothrow
		=> _impl !is null && _impl.fd;

	// if open, closes, else does nothing
	void close()
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

		driverfp().releaseRef(_impl.fd); // close
	}

	static if (!IS_PIPE)
	void sync()
	{
		// TODO: Windows support
		// TODO: Darwin support
		import core.sys.posix.unistd : fsync;
		import std.exception : errnoEnforce;

		errnoEnforce(fsync(fileno) == 0);
	}

	@property int fileno() const
	{
		auto fd = _impl.fd.value.value;
		assert(fd < int.max);
		return cast(int) fd;
	}

	static if (!IS_PIPE)
	@property ulong length() const
	{
		return eventDriver.files.getSize(_impl.fd);
	}

	// TODO: truncate

	// make the offset arg only exist for files without having to declare the functions twice
	static if (IS_PIPE)
		private alias OFFSET_ARGS = AliasSeq!();
	else
		private alias OFFSET_ARGS = AliasSeq!ulong;

	static if (READABLE)
	ulong read(OFFSET_ARGS oset, ubyte[] buf) @Async
	{
		return withLock({
			static if (IS_PIPE)
				auto res = pipeRead(_impl.fd, buf);
			else
				auto res = fileRead(_impl.fd, oset[0], buf);

			check!(IOStatus.ok, (s) => "read error: " ~ s)(res.status);
			return res.bytesRWd;
		});
	}

	static if (WRITEABLE)
	ulong write(OFFSET_ARGS oset, const(ubyte)[] buf) @Async
	{
		return withLock({
			static if (IS_PIPE)
				auto res = pipeWrite(_impl.fd, buf);
			else
				auto res = fileWrite(_impl.fd, oset[0], buf);

			check!(IOStatus.ok, (s) => "write error: " ~ s)(res.status);
			return res.bytesRWd;
		});
	}
}

// wraps a file handle
alias FileH = Handle!false;
// wraps one end of a pipe handle
alias PipeEndHR = Handle!(true, true, false);
alias PipeEndHW = Handle!(true, false);
alias PipeEndHA = Handle!true;

// wraps a complete pipe with a read and write end
struct Pipe
{
	private PipeEndHR _read;
	private PipeEndHW _write;

	@property PipeEndHR readEnd() nothrow { return _read; }
	@property PipeEndHW writeEnd() nothrow { return _write; }

	@property auto readStream() nothrow { return readStreamify(_read); }
	@property auto writeStream() nothrow { return writeStreamify(_write); }

	// generally should be unnecessary, as both pipes will automatically close themselves when
	// there are no more references to them
	void close()
	{
		_read.close();
		_write.close();
	}

	// creates a pipe!
	// cannot just be a default constructor for struct reasons
	static Pipe create()
	{
		// https://github.com/dlang/phobos/blob/c970ca6/std/process.d#L2756
		version (Posix)
		{
			import core.sys.posix.unistd : pipe;
			int[2] fds;
			check!(0, (_) => "failed to open pipe")(pipe(fds));

			return Pipe(PipeEndHR(fds[0], false), PipeEndHW(fds[1], false));
		}
		else
		{
			// TODO
		}
	}
}

enum SeekOrigin
{
	set,
	curr,
	end
}

// assumes you already have a `H handle` in your struct
mixin template StreamIndexManagement()
{
	private ulong _index;
	private bool _eof;

	@property ulong tell() const { return _index; }

	// forward length from handle for convenience
	@property ulong length() const { return handle.length; }

	@property bool isEof() const { return _eof; }

	void seek(long oset, SeekOrigin origin = SeekOrigin.set)
	{
		import std.exception : enforce;

		auto len = length;

		final switch (origin) with(SeekOrigin)
		{
			case set:
				enforce(oset < len, "cannot seek past the end of the stream");
				_index = oset;
				break;

			case curr:
				enforce(oset >= 0 || -oset > _index, "cannot seek before the start of the stream");
				enforce((oset + _index) <= len, "cannot seek past the end of the stream");
				_index += oset;
				break;

			case end:
				enforce(oset <= 0, "cannot seek past the end of the stream");
				_index = len + oset;
				break;
		}

		checkEOF(len);
	}

	private void checkEOF()
	{
		checkEOF(length);
	}

	private void checkEOF(ulong l)
	{
		_eof = _index == l;
	}
}

struct ReadStream(H) if (isInstanceOf!(Handle, H) && H.isReadable)
{
	H handle;

	// position management
	static if (!H.isPipe) mixin StreamIndexManagement!();

	// TODO: actually implement
}

struct WriteStream(H) if (isInstanceOf!(Handle, H) && H.isWriteable)
{
	H handle;

	// position management
	static if (!H.isPipe) mixin StreamIndexManagement!();
}

// this sucks but idk what else to do because of template arg inference
auto readStreamify(H)(scope H value) if (isInstanceOf!(Handle, H) && H.isReadable)
{
	return ReadStream!H(value);
}
auto writeStreamify(H)(scope H value) if (isInstanceOf!(Handle, H) && H.isWriteable)
{
	return WriteStream!H(value);
}

import core.sys.posix.unistd : STDIN_FILENO, STDOUT_FILENO, STDERR_FILENO;

auto getStdin() @property // @suppress(dscanner.confusing.function_attributes)
{
	int fd;
	// TODO: other platforms than POSIX
	version (Posix)
	{
		import core.sys.posix.unistd : dup;
		fd = dup(STDIN_FILENO);
		assert(fd);
	}

	return readStreamify(PipeEndHR(fd, false));
}

auto getStdout() @property // @suppress(dscanner.confusing.function_attributes)
{
	int fd;
	version (Posix)
	{
		import core.sys.posix.unistd : dup;

		fd = dup(STDOUT_FILENO);
		assert(fd);
	}

	return writeStreamify(PipeEndHW(fd, false));
}

auto getStderr() @property // @suppress(dscanner.confusing.function_attributes)
{
	int fd;
	version (Posix)
	{
		import core.sys.posix.unistd : dup;

		fd = dup(STDERR_FILENO);
		assert(fd);
	}

	return writeStreamify(PipeEndHW(fd, false));
}
