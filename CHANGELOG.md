## Pending
- Docs improvements
  * Note about busy wait dangers with `yield`
- Finalize most classes that are used only for their reference semantics (and lock support), not for inheritance
  * Affects `synct.*` and `reactor.Reactor.WrappedFiber`
  * Relatedly, remove some `shared` keywords in `synct` for members inside a shared class, which were doing nothing.

## `0.0.1-beta.1`

- Initial release! :tada:
- Initial reactor round-robin implementation
- `llevents` bindings for all eventcore APIs except directory watchers
- Task abstraction
- Many fiber syncing primitives
- Minimal thread syncing primitives (event and semaphore)
- Basic threading tools
