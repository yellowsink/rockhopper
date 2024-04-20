// `task` provides a very minimal task implementation on top of fibers.

module task;

import core.reactor : spawn; // used in constructor and in then
import sync : FEvent; // used for syncing the fibers

import std.typecons : Nullable; // used by tryGetRes

import std.traits : isSomeFunction, Parameters, ReturnType; // used for template inference stuff

struct Task(T)
{
	enum VALUED = !is(T == void);

	private FEvent ev;

	static if(VALUED)
		private T res;

	// may only call this with T function() or T delegate()
	// we use a separate function to wrap this so we can infer the type T from F.
	private this(F)(F dg)
	{
		static assert(isSomeFunction!F && Parameters!F.length == 0 && is(ReturnType!F == T));

		spawn({
			static if(VALUED)
				res = dg();
			else
				dg();
			ev.notify();
		});
	}

	bool isFinished() inout @property
	{
		return ev.isSignaled;
	}

	static if(VALUED)
		alias MAYBERES = Nullable!T;
	else
		alias MAYBERES = bool;

	MAYBERES tryGetRes()
	{
		static if(!VALUED)
			return isFinished;
		else
			return isFinished ? MAYBERES(res) : MAYBERES.init;
	}

	T waitRes()
	{
		ev.wait();
		static if(VALUED) return res;
	}

	auto then(F)(F fn)
	if (VALUED && isSomeFunction!F && Parameters!F.length == 1 && is(Parameters!F[0] == T))
	{
		return Task!(ReturnType!F)({
			return fn(waitRes());
		});
	}

	auto then(F)(F fn)
	if (!VALUED && isSomeFunction!F && Parameters!F.length == 0)
	{
		return Task!(ReturnType!F)({
			waitRes();
			fn();
		});
	}
}

auto tSpawn(F)(F fn)
if (isSomeFunction!F && Parameters!F.length == 0)
{
	return Task!(ReturnType!F)(fn);
}
