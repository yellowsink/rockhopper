# `rockhopper.core`

The `core` APIs are the most fundamental in Rockhopper. They are prone to mistakes if misused, and are not complete -
that is, they generally contain only operations that are async, and leave out synchronous but relevant operations.

There are four parts that make these APIs up:

The Rockhopper `reactor` is the most important part of Rockhopper.
You have one reactor per thread, which is responsible for scheduling your fibers - that is, when you `yield()`, control
flow is passed to the reactor, which will eventually pass it back to you.
It is also the reactor's job to make sure the thread suspends at the right time and wakes back up at the right time.

The exposed APIs from the reactor are generally in two camps: those used to help you work with fibers,
and those that are internally used to implement `llevents`.

`llevents` is a set of functions that expose the basic functionality of Rockhopper to you.
This is where you will find functions with promising names such as `fileRead` and `sleep`.
This is what the rest of Rockhopper's APIs are built upon, and almost all of these are *async*.

`suspends` contains type definitions.
It generally serves two jobs:
 - An implementation detail - these are the types passed to the reactor to tell it what your fiber is waiting for,
   and what the reactor will give you back when it's done.
 - Return types - `llevents` will often return structs from here back to you.

`threading` has tools for managing threads. It is unlikely that your app will need threads, but if it does, these are
the tools to use to manage them.
