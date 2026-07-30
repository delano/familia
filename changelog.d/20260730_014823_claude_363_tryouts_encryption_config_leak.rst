Fixed
-----

- Tryout files no longer leak their encryption config into the rest of the run.
  ``Familia.config.encryption_keys`` and ``current_key_version`` are
  process-global and the tryouts runner evaluates every file in one process, so
  a file that set them and never cleared them left them installed for whatever
  ran next. Running each such file followed by a probe that asserts both settings
  are nil confirmed nineteen leakers. No test failed as a result, which was the
  hazard: a file that believed it had configured its own key material could be
  exercising a neighbour's, and an encryption test passing under the wrong key is
  not testing what it claims. Adding a file that requires the keys to be *absent*
  would also have passed or failed depending on where it sorted. Every file that
  touches the encryption config now installs it through a scoped helper and hands
  back the previous config when it finishes. #363

- ``try/features/real_feature_integration_try.rb`` was the leak's confirmed
  victim. It declares an ``encrypted_field`` and assigns it during setup but
  never configured any key material, so it had been running on whatever the
  previous file in the run happened to leave installed. It fails outright when
  run on its own -- ``Key version cannot be nil`` -- which is what closing the
  leak made it do in the full suite as well. It now installs its own keyring.
  #363

- ``try/features/encryption/module_loading_try.rb`` leaked too, under a spelling
  the original survey missed: ``Familia.encryption_keys=`` and
  ``Familia.config.encryption_keys=`` are the same setting, because
  ``Familia.config`` returns ``Familia`` itself. The new helper's leak warning is
  what surfaced it. #363

- The teardown line ``Fiber[:familia_key_cache]&.clear`` in eight encryption
  tryouts was a no-op -- the derived-key cache lives under
  ``Fiber[:familia_request_cache]``, so nothing was ever cleared. Those teardowns
  now go through the helper, which wipes the real cache. #363

Added
-----

- ``try/support/helpers/encryption_config.rb``, loaded by ``test_helpers``, with
  three helpers for tryouts that need encryption keys:
  ``set_test_encryption_keys(keys, current_version:)`` installs a keyring and
  records what it displaced, ``clear_test_encryption_keys`` puts that back (used
  in teardown), and ``with_test_encryption_keys(keys, current_version:) { ... }``
  scopes an override to a single test case and restores it even when the block
  raises. Restoring means restoring the *previous* values rather than nilling
  them, so the two forms nest. Repeat calls to ``set_test_encryption_keys`` in
  one file are safe: only the first records the baseline. The baseline is scoped
  to the file that recorded it, so a file that installs keys and then forgets its
  teardown does not suppress the next file's leak check or become what that file
  restores to -- the next install warns and baselines to the empty keyring, which
  ends the leak there rather than passing it along. Each install and
  restore also wipes the fiber-local derived-key cache, which is keyed by version
  and context rather than by the master key an entry came from and so would
  otherwise survive a keyring swap. When a file installs keys and finds the
  config already populated -- the signature of an earlier file that forgot its
  teardown -- the helper warns on stderr naming the file, so the next such
  omission is loud instead of silent. #363

AI Assistance
-------------

- AI wrote the scoped-config helper and migrated every tryout that touches the
  encryption config to it: the files with no teardown, and the files that already
  cleaned up by assigning ``nil`` or by hand-rolling their own save/restore.
  Added ``try/support/encryption_config_helper_try.rb`` covering install/restore,
  block nesting inside a file-scoped override, restoration when the block raises,
  the repeat-install baseline rule, the clear-with-no-install fallback, the leak
  warning, and the derived-key cache wipe. Verified the fix by running every
  encryption-touching file followed by a leak probe -- nineteen fail that probe
  before the change, none after. #363
