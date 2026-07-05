Changed
-------

- ``Familia::Encryption::Registry.get`` now distinguishes an unknown algorithm
  from a *known* algorithm whose provider is not available on the current node.
  Because ``Registry.register`` only stores providers whose runtime dependency is
  present, pinning ``encrypted_field ..., algorithm: 'xchacha20poly1305'`` on a
  node without ``rbnacl``/libsodium previously raised the misleading
  ``"Unsupported algorithm: xchacha20poly1305"`` -- pointing an operator at a typo
  when the real fix is a missing dependency. It now names the provider, explains
  the dependency is missing, and lists the algorithms actually available. The set
  of registerable providers is centralized in ``Registry.known_providers``, the
  single source of truth shared by ``setup!`` and ``get``. Error-message and
  internal-refactor only; the resolution of every available algorithm is
  unchanged. Issue #334

AI Assistance
-------------

- The registry error-message refinement, its regression tryout, and this
  changelog entry were drafted with AI assistance. Issue #334
