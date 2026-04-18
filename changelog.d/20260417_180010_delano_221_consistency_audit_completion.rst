Fixed
-----

- ``AuditReport#healthy?`` now also considers the ``missing`` bucket entries
  returned by class-level multi-index audits. Previously a report could show
  ``status: :issues_found`` for multi-indexes while still reporting
  ``healthy? == true`` whenever only ``missing`` entries existed, misleading
  any caller using ``healthy?`` as a health gate.
- ``AuditReport#to_h`` and ``AuditReport#to_s`` now include the ``missing``
  count in their multi-indexes output, bringing the summary shape in line with
  the unique-indexes output. PR #221.

AI Assistance
-------------

- AI-assisted implementation of the ``healthy?`` / ``to_h`` / ``to_s`` fix and
  the corresponding regression tests in
  ``try/audit/audit_report_try.rb`` and
  ``try/audit/m3_multi_index_stub_try.rb``.
