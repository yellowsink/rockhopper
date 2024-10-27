// `uda` contains user defined attributes useful for introspection with rockhopper.
module rockhopper.core.uda;

private {
	struct _Async {} // @suppress(dscanner.style.phobos_naming_convention)
	struct _ThreadSafe {} // @suppress(dscanner.style.phobos_naming_convention)
	struct _Synchronized {} // @suppress(dscanner.style.phobos_naming_convention)
}

// `@Async` functions may only be called from within an event loop, and may suspend your fiber
enum Async = _Async.init;

// `@ThreadSafe` struct and class instances can be shared across threads
enum ThreadSafe = _ThreadSafe.init;

// `@Synchronized` functions act like the built in `synchronized` attr, but for fibers not just threads
enum Synchronized = _Synchronized.init;

import std.traits : hasUDA;

alias isAsync(alias F) = hasUDA!(F, Async);
alias isThreadSafe(alias F) = hasUDA!(F, ThreadSafe);
alias isSynchronized(alias F) = hasUDA!(F, Synchronized);

// TODO: is there some way to check if a function uses an @Async function with just a template...
