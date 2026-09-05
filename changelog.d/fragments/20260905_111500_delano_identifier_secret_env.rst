Added
-----

- ``Familia::VerifiableIdentifier.secret_key`` now reads ``IDENTIFIER_SECRET``
  when ``VERIFIABLE_ID_HMAC_SECRET`` is unset or blank. ``VERIFIABLE_ID_HMAC_SECRET``
  remains supported and takes precedence when nonblank. ``KeyError`` is still
  raised on first use when neither variable holds a nonblank value. (#423)

Changed
-------

- A blank ``VERIFIABLE_ID_HMAC_SECRET`` no longer raises on its own; it falls
  through to ``IDENTIFIER_SECRET``. Deployments that set only the legacy variable
  are unaffected. Applications that bridge
  ``ENV['VERIFIABLE_ID_HMAC_SECRET'] ||= ENV['IDENTIFIER_SECRET']`` can remove
  the bridge. See ``docs/migrating/identifier-secret.md``. (#423)
