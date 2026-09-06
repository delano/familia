Added
-----

- Added ``Horreum.configure_related_field(name, **opts)``, which merges options
  into a declared related-field definition (``sorted_set``, ``list``, ``set``,
  ``hashkey``, and the ``class_*`` variants) at boot, after config is loaded.
  Options are validated eagerly with the same rules and errors the DataType
  raises at construction (``max_length:`` must be a positive Integer and is
  only accepted on ``SortedSet``/``ListKey``, ``dirty_write_warnings:`` must be
  a valid mode, the old ``:maxlength`` spelling warns). An unknown field name
  raises ``ArgumentError``. (#428)
- Related-field definitions now freeze at first use: instance-level definitions
  when the class first materializes its collections (first instance created or
  loaded), class-level definitions on the first accessor call. After that,
  ``configure_related_field`` raises ``Familia::RelatedFieldFrozenError`` (a
  ``Familia::Problem`` naming the class and field) and direct mutation of
  ``Klass.related_fields[:x].opts`` raises ``FrozenError``. The freeze is per
  class; subclasses and anonymous classes get a fresh window. (#428)

Changed
-------

- Re-declaring a related field whose definition has already materialized
  (``sorted_set :events`` again after an instance exists, or a ``class_*``
  field again after its accessor was called) now raises
  ``Familia::RelatedFieldFrozenError`` instead of silently replacing the
  definition and leaving earlier instances (or the cached class-level
  collection) on the old options. Re-declaring before first use still
  replaces the definition, and declaring a new name on a materialized class
  is still allowed. (#428)
- ``configure_related_field`` takes an optional ``scope:`` keyword
  (``:instance`` or ``:class``) for the case where the same name is declared
  at both levels (``zset :instances`` next to the automatic
  ``class_sorted_set :instances``). Without it the instance-level definition
  is addressed when both exist, as before. (#428)
- Class-level related fields validate their options at the declaration line
  again (``class_set :tags, max_length: 5`` raises there, not on first
  access), matching instance-level fields, which now also validate at
  declaration rather than on the first ``Klass.new``. (#428)
- The first materialization of a class's instance-level fields now holds
  ``related_fields_mutex`` for the whole read-build-freeze pass, so a
  ``configure_related_field`` racing the first ``Klass.new`` either applies
  to every instance or raises; it can no longer land between the build and
  the freeze. (#428)

- Class-level collections (``class_sorted_set``, ``class_list``, ...) are built
  lazily on the first accessor call instead of at declaration. ``Klass.name``,
  ``Klass.name=``, and ``Klass.name?`` behave the same from the caller's view.
  (#428)
- ``initialize_relatives`` no longer writes ``parent`` into the shared
  definition Hash, which was a race when two instances of the same class
  materialized concurrently. (#428)
- Subclasses now receive their own copies of related-field definitions rather
  than sharing the parent's, so configuring or freezing one class does not
  affect another. (#428)
- A subclass that inherits a class-level field (``class_sorted_set``,
  ``class_list``, ...) without re-declaring it now gets a working accessor
  where it previously returned ``nil``. The copied definition's ``parent`` is
  re-pointed at the subclass, so ``Tenant.registry`` is keyed under ``Tenant``
  (like ``instances`` already was) rather than aliasing
  ``Organization.registry``. Set ``prefix`` on the base class to share keys
  across the hierarchy. (#428)

Fixed
-----

- ``Familia::ThreadSafety::InstrumentedMutex#synchronize`` did not acquire
  the underlying mutex unless the thread-safety monitor was enabled, which it
  is not by default. Every class-level registry guard built on it
  (``fields_mutex``, ``field_types_mutex``, ``field_groups_mutex``,
  ``related_fields_mutex``, the connection-chain mutex) was therefore a
  no-op in normal operation. It now always locks. (#428)
