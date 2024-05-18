## Pending
- Docs improvements
  * Note about busy wait dangers with `yield`
- Finalize `synct` classes, as they are used only for their reference semantics (and lock support), not for OOP
  * Relatedly, remove some `shared` keywords in `synct` for members inside a shared class, which were doing nothing.
- Swap `reactor.Reactor.WrappedFiber` from a class to a struct. This has no *real* effect but I prefer it.
- Remove pointless (and likely slow) atomics from `TSemaphore`, as the value is protected by a lock anyway.
- Add a custom allocator for `WrappedFiber` & `Fiber` instances in reactor, based on freelists.
  This will reduce the required amount of allocations for `spawn()` once fibers start terminating, therefore cheapening
  fibers even more. This does not affect having to allocate memory using mmap for the actual stack.
  This should also reduce memory use in the long term as this can reuse memory much more efficiently than the D
  conservative GC can free it.

## `0.0.1-beta.1`

- Initial release! :tada:
- Initial reactor round-robin implementation
- `llevents` bindings for all eventcore APIs except directory watchers
- Task abstraction
- Many fiber syncing primitives
- Minimal thread syncing primitives (event and semaphore)
- Basic threading tools
