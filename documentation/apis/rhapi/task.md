# `rockhopper.rhapi.task`

Rockhopper generally is not built around tasks. Tasks add a lot of overhead and noise, and often are not really
necessary.
Every time you see something like `await DoSomethingAsync();`, you're seeing a task instantly created then awaited,
so it's not being used for any real purpose.
This is why Rockhopper APIs just implicitly suspend your fiber, instead of using a task model.

Despite this choice, tasks can still sometimes be a useful tool, so you can still choose to use them if you like.

## `Task(T)`

```d
struct Task(void)
{
	bool isFinished();
	bool tryGetRes();
	T waitRes(); [ASYNC]
	R then(R delegate());
	R then(R function());
}

struct Task(T) // where T is not void
{
	bool isFinished();
	Nullable!T tryGetRes();
	T waitRes(); [ASYNC]
	R then(R delegate(T));
	R then(R function(T));
}
```

The task struct represents an asynchronous job that may be either running or complete.
Calling `waitRes` will return instantly if the task is complete, or yield your fiber if not,
like `await` in most languages.

`then` allows you to chain the result of a task into another function, back into a task.
The API has been designed such that type inference should work automatically.

## `tSpawn`

```d
R tSpawn(R function());
R tSpawn(R delegate());
```

Spawns a task that runs the given function as a fiber, and completes when it returns a value.

## `taskify(F)`

```d
auto taskify(alias F)(Parameters!F)
```

`taskify` is a template that helps you more easily use async APIs in task-oriented code.
It wraps a function to run inside a task.

## Example

```d
// create a task
auto t = tSpawn({
	writeln("1");

	sleep(dur!"msecs"(500));

	writeln("2");
	return "hello there";
});

writeln("1");

auto t2 = t.then((string s) {
	writeln(s);
});

t2.waitRes(); // wait for task to finish
assert(t.isFinished);

// bonus: create a task using an async function
import rockhopper.core.llevents : nsLookup;

auto dnsTask = taskify!nsLookup("google.com");
```
