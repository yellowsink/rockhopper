## `rockhopper.rhapi`

RHApi is the primary API for interacting with Rockhopper.
It is designed to be friendly, safe, and flexible.

It contains helpful wrappers around all Rockhopper functionality, such as files and processes, but also contains
helpful utilities that make working with Rockhopper much easier, such as sync primitives.

[`task`](task.md) contains the task abstraction, for promise/task/future-based programming patterns.

[`syncf` and `synct`](sync.md) contains synchronization tools to help you coordinate fibers and threads.
All `syncf` members are NOT thread-safe, stack-allocated, need no initialization, and designed for efficiency.
All `synct` members are thread-safe and use reference semantics (classes), therefore needing runtime construction.

[`file`](file.md) contains tools for working nicely with files and pipes.
