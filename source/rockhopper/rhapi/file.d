module rockhopper.rhapi.file;

import rockhopper.core.reactor;
import rockhopper.core.uda;

public import eventcore.driver : FileOpenMode;
import eventcore.driver : FileFD, PipeFD, OpenStatus, IOStatus;

import std.traits : isInstanceOf;

// are you god damn kidding me
version (OSX) version = Darwin;
version (iOS) version = Darwin;
version (TVOS) version = Darwin;
version (WatchOS) version = Darwin;
version (VisionOS) version = Darwin;


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
		import std.exception : errnoEnforce;

		version (Windows)
		{
			import core.sys.windows.basetsd : HANDLE;
			import core.sys.windows.winbase : FlushFileBuffers;

			size_t hdl_raw = _impl.fd.value.value;
			HANDLE hdl = cast(HANDLE) hdl_raw;

			errnoEnforce(FlushFileBuffers(hdl) == 0);
		}
		else version (Darwin)
		{
			// https://transactional.blog/blog/2022-darwins-deceptive-durability
			// fsync is not enough
			import core.sys.darwin.fcntl : fcntl, F_FULLFSYNC;

			errnoEnforce(fcntl(fileno(), F_FULLFSYNC) != -1);
		}
		else
		{
			import core.sys.posix.unistd : fsync;

			errnoEnforce(fsync(fileno) == 0);
		}
	}

	// returns int on posix, HANDLE on windows
	@property auto fileno() const
	{
		auto fd = _impl.fd.value.value;
		assert(fd < int.max);

		version (Windows)
		{
			import core.sys.windows.basetsd : HANDLE;
			return cast(HANDLE) fd;
		}
		else
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

	@property auto readStream() nothrow { return streamify(_read); }
	@property auto writeStream() nothrow { return streamify(_write); }

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
			static assert(0, "not implemented yet");
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

struct Stream(H, ulong BUFSIZE = 256) if (isInstanceOf!(Handle, H))
{
	H handle;

	enum isSeekable = !H.isPipe;
	enum isReadable = H.isReadable;
	enum isWriteable = H.isWriteable;

	// position management
	static if (isSeekable)
	{
		private ulong _index;
		private bool _eof;

		@property ulong tell() const
		{
			return _index;
		}

		// forward length from handle for convenience
		@property ulong length() const
		{
			return handle.length;
		}

		@property bool isEof() const
		{
			return _eof;
		}

		void seek(long oset, SeekOrigin origin = SeekOrigin.set)
		{
			import std.exception : enforce;

			auto len = length;

			final switch (origin) with (SeekOrigin)
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

	static if (isReadable)
	// reads into a buffer, updating the index and eof state as necessary, returning the amount written
	ulong rawRead(ubyte[] buffer) @Async
	{
		static if (!isSeekable) return handle.read(buffer);
		else
		{
			ulong bytesXfered;

			// we only check if this read will EOF using the file length if an error occurs,
			// as checking length() every time would be relatively expensive.
			try
			{
				bytesXfered = handle.read(_index, buffer);
			}
			catch (FileIOException e)
			{
				auto fileLen = length();

				if (
					// error state MIGHT BE an EOF
					e.status == IOStatus.error
					// this read indeed would have EOFed
					&& _index + buffer.length > fileLen)
				{
					bytesXfered = fileLen - _index;
					_eof = true;
				}
				else
					throw e;
			}

			_index += bytesXfered;

			return bytesXfered;
		}
	}

	static if (isWriteable)
	// reads into a buffer, updating the index and eof state as necessary, returning the amount written
	ulong rawWrite(const(ubyte)[] buffer) @Async
	{
		static if (!isSeekable) return handle.write(buffer);
		else
		{
			ulong bytesXfered;

			try
			{
				bytesXfered = handle.write(_index, buffer);
			}
			catch (FileIOException e)
			{
				auto fileLen = length();

				if (
					// error state MIGHT BE an EOF
					e.status == IOStatus.error
					// this read indeed would have EOFed
					&& _index + buffer.length > fileLen)
				{
					bytesXfered = fileLen - _index;
					_eof = true;
				}
				else
					throw e;
			}

			_index += bytesXfered;

			return bytesXfered;
		}
	}

	static if (isReadable)
	ubyte[] rawRead(ulong upTo) @Async
	{
		ubyte[] buf = new ubyte[upTo];
		auto xfered = rawRead(buf);
		return buf[0 .. xfered];
	}

	// TODO: r/w buffering

	/* APIs to implement:
	copyto
	read
	readatleast
	readbyte
	readexactly
	write
	range support
	 - chunk
	 - directly as bytes
	 - by line
	 */

	// TODO: nice apis
}

// this sucks but idk what else to do because of template arg inference
auto streamify(H)(scope H value) if (isInstanceOf!(Handle, H))
{
	return Stream!H(value);
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

	return streamify(PipeEndHR(fd, false));
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

	return streamify(PipeEndHW(fd, false));
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

	return streamify(PipeEndHW(fd, false));
}
