.. Added
.. -----

.. Changed
.. -------

- **ExternalIdentifier Format Flexibility**: The `external_identifier` feature now supports customizable format templates via the `format` option. This allows you to control the separator and overall format of generated external IDs beyond just the prefix.

  **Default format** (unchanged behavior):

  .. code-block:: ruby

     class User < Familia::Horreum
       feature :external_identifier
     end
     user.extid  # => "ext_abc123def456ghi789"

  **Custom separator** (using prefix only):

  .. code-block:: ruby

     class Customer < Familia::Horreum
       feature :external_identifier, prefix: 'cust'
     end
     customer.extid  # => "cust_abc123def456ghi789"

  **Custom format template** (full control):

  .. code-block:: ruby

     class APIKey < Familia::Horreum
       feature :external_identifier, format: '%{prefix}-%{id}'
     end
     key.extid  # => "ext-abc123def456ghi789"

     class Resource < Familia::Horreum
       feature :external_identifier, format: 'api/%{id}'
     end
     resource.extid  # => "api/abc123def456ghi789"

  The `format` option accepts a Ruby format string with two placeholders: `%{prefix}` for the configured prefix (default: "ext") and `%{id}` for the generated identifier. This provides flexibility for various ID formatting needs including URL paths, different separators (hyphen, slash, etc.), or no separator at all.

.. Deprecated
.. ----------

.. Removed
.. -------

.. Fixed
.. -----

.. Security
.. --------

.. Documentation
.. -------------

.. AI Assistance
.. -------------

- **Design Review**: Claude Code provided analysis of the current implementation and recommended several idiomatic Ruby approaches for format flexibility, ultimately suggesting the format template pattern using Ruby's native string formatting.
- **Implementation**: Claude Code implemented the format template feature including code changes, test cases, and documentation updates.
