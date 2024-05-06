// `task` provides a very minimal task implementation on top of fibers.

module rockhopper.rhapi.task;

import rockhopper.core.reactor : spawn; // used in constructor and in then
import rockhopper.rhapi.syncf : FEvent; // used for syncing the fibers

import std.typecons : Nullable; // used by tryGetRes

import std.traits : isSomeFunction, Parameters, ReturnType; // used for template inference stuff

struct Task(T)
{
	enum VALUED = !is(T == void);

	private FEvent ev;

	static if(VALUED)
		private T res;

	// disable copying struct
	@disable this(ref Task);

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

	static if(VALUED)
	{
		private this(T value)
		{
			res = value;
			ev.notify(); // this is so jank lmao
		}
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

auto taskify(alias F)(Parameters!F params)
{
	return tSpawn({ return F(params); });
}

auto completedTask(T)(T value)
{
	return Task!T(value);
}

void waitAllTasks(T)(Task!T*[] tasks)
{
	foreach (t; tasks) t.waitRes(); // lol
}

// heterogenous version
void waitAllTasks(TASKS...)()
{
	import std.traits : isInstanceOf;

	static foreach(t; TASKS)
	{
		static assert(isInstanceOf!(Task, typeof(t)), "Cannot pass a value to waitAllTasks that is not a Task");

		t.waitRes(); // lol it really is that shrimple
	}
}

void waitAnyTask(T)(Task!T*[] tasks)
{
	FEvent ev;

	foreach (t; tasks)
		static if (is(T == void))
			t.then({ ev.notify(); });
		else
			t.then((T _) { ev.notify(); });

	ev.wait();
}

// heterogenous
void waitAnyTask(TASKS...)()
{
	import std.traits : isInstanceOf, TemplateArgsOf;

	FEvent ev;

	static foreach(t; TASKS)
	{{
		alias TTask = typeof(t);

		static assert(isInstanceOf!(Task, TTask), "Cannot pass a value to waitAnyTask that is not a Task");

		alias TValue = TemplateArgsOf!TTask[0];

		static if (is(TValue == void))
			t.then({ ev.notify(); });
		else
			t.then((TValue _) { ev.notify(); });
	}}

	ev.wait();
}
