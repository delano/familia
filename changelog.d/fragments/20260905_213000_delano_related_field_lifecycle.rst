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
