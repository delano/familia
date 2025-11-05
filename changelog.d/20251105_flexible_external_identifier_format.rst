.. Added
.. -----

.. Changed
.. -------

- **ExternalIdentifier Format Flexibility**: The `external_identifier` feature now supports customizable format templates via the `format` option. This allows you to control the entire format of generated external IDs, including the prefix, separator, and overall structure.

  **Default format** (unchanged behavior):

  .. code-block:: ruby

     class User < Familia::Horreum
       feature :external_identifier
     end
     user.extid  # => "ext_abc123def456ghi789"

  **Custom format with different prefix**:

  .. code-block:: ruby

     class Customer < Familia::Horreum
       feature :external_identifier, format: 'cust_%{id}'
     end
     customer.extid  # => "cust_abc123def456ghi789"

  **Custom format with different separator**:

  .. code-block:: ruby

     class APIKey < Familia::Horreum
       feature :external_identifier, format: 'api-%{id}'
     end
     key.extid  # => "api-abc123def456ghi789"

  **Custom format without traditional prefix**:

  .. code-block:: ruby

     class Resource < Familia::Horreum
       feature :external_identifier, format: 'v2/%{id}'
     end
     resource.extid  # => "v2/abc123def456ghi789"

  The `format` option accepts a Ruby format string with the `%{id}` placeholder for the generated identifier. The default format is `'ext_%{id}'`. This provides complete flexibility for various ID formatting needs including different prefixes, separators (underscore, hyphen, slash), URL paths, or no prefix at all.

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
