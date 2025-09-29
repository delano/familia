Changed
-------

- Renamed DataType classes to avoid Ruby namespace confusion: ``Familia::String`` → ``Familia::StringKey``, ``Familia::List`` → ``Familia::ListKey``
- Added dual registration for both traditional and explicit method names (``string``/``stringkey``, ``list``/``listkey``)
- Updated ``Counter`` and ``Lock`` to inherit from ``StringKey`` instead of ``String``

Documentation
-------------

- Updated overview documentation to explain dual naming system and namespace safety benefits
- Enhanced examples to demonstrate both traditional and explicit DataType method naming

AI Assistance
-------------

- DataType class renaming and dual registration system implementation designed and developed with Claude Code assistance
- All test updates and documentation enhancements created with AI support
