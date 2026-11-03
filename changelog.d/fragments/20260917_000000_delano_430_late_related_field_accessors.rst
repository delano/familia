Fixed
-----

- A related field declared after an instance of the class already existed
  (``participates_in`` finishing at load while an early request holds an
  instance, or any late ``Klass.list :x``) is now built by that instance's
  accessor on first access instead of raising ``RuntimeError: <Class>#<field>
  is nil. Did you override initialize without calling super?``. The cascades
  that walk the current registry (``update_expiration``, ``persist!``,
  ``ttl_report``, instance ``destroy!``) therefore work on instances created
  before the declaration. The field is built once per instance, from the
  current definition, under the class's build lock (concurrent first access
  constructs it once), and that first build freezes the definition like any
  other materialization. Already-built fields are never rebuilt. An accessor
  inherited from an ancestor that declared the field after the subclass was
  defined has no definition in the subclass registry and raises
  ``Familia::HorreumError`` naming that gap. (#430)
- A related-field declaration (instance-level or ``class_*``) now defines the
  accessors before it inserts the definition into the registry. The cascades
  above snapshot the registry and call ``send(name)``; a snapshot taken
  between the insert and the accessor definition could call a method that
  did not exist yet and raise ``NoMethodError``. (#430)
