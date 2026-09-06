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
- Declaration, re-declaration, ``configure_related_field`` and the freeze
  all serialize on the class's ``related_fields_mutex``, which is now created
  eagerly when the class is defined (``@mutex ||=`` let two first callers
  allocate separate mutexes). The first materialization freezes the
  definitions under that lock before building, so a configure or a
  re-declaration racing the first ``Klass.new`` or the first class-level
  accessor call either applies everywhere (instances and registry) or
  raises; it can no longer leave the first instance or the cached collection
  on old options while the registry shows new ones. (#428)
- DataType construction runs outside ``related_fields_mutex``. A custom
  DataType whose ``init`` (or an option setter) reads another collection of
  the same class no longer raises ``ThreadError: deadlock; recursive
  locking`` during an instance-level or class-level build. (#428)
- Class-level collections are built single-flight under a per-class
  reentrant build lock: concurrent first calls to ``Klass.registry`` construct
  the DataType (and run a custom ``init``) exactly once instead of once per
  caller with all but one result discarded. (#428)
- The first ``Klass.new`` builds its collections from a snapshot of the
  related-field registry taken under ``related_fields_mutex`` instead of
  iterating the live Hash, so a new field declared concurrently (as
  ``participates_in`` does at load) no longer raises ``RuntimeError: can't
  add a new key into hash during iteration``. (#428)
- Lazily built class-level collections are cached in a per-class Hash
  (``Klass.class_related_field_cache``) instead of ``@<name>`` on the class,
  so a pre-existing class instance variable with the field's name is never
  returned in place of the collection. (#428)

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
