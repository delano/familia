# try/support/helpers/encryption_config.rb
#
# frozen_string_literal: true

# Scoped encryption config for tryouts (issue #363).
#
# `Familia.config.encryption_keys` and `Familia.config.current_key_version` are
# process-global, and the tryouts runner evaluates every file in a single
# process. A file that assigns them directly leaves them installed for whatever
# runs next, so a later file silently reads a neighbour's key material and the
# suite becomes order-dependent. Nothing fails visibly -- which is the hazard: an
# encryption test that passes under someone else's key is not testing what it
# claims, and a file that needs the keys *absent* passes or fails depending on
# where it sorts.
#
# Use these helpers instead of assigning the config directly.
#
# File-scoped, the common case -- setup installs, teardown restores:
#
#   set_test_encryption_keys({ v1: Base64.strict_encode64('a' * 32) },
#                            current_version: :v1)
#
#   ## ...test cases...
#
#   clear_test_encryption_keys
#
# Calling #set_test_encryption_keys more than once in a file is fine: only the
# first call records what to restore, so a setup that installs one keyring and
# then widens it still hands back the pre-file config, not the intermediate one.
#
# Single test case, restoring itself even when the block raises:
#
#   ## Ciphertext under a retired key version still decrypts
#   with_test_encryption_keys(@keys, current_version: :v2) do
#     Familia::Encryption.decrypt(@envelope, context: 'ctx')
#   end
#   #=> 'plaintext'
#
# The block restores exactly what it displaced, so it nests inside a file-scoped
# override: on exit the file's own keyring is back, not the empty keyring.
module TestEncryptionConfig
  Snapshot = Struct.new(:keys, :version)

  # The config displaced by the current file's first #install, and which file
  # that was. The baseline is only meaningful to its own file: a baseline still
  # standing when a *different* file installs means the first file never
  # restored, which #install treats as the leak it is rather than inheriting.
  @baseline = nil
  @baseline_file = nil

  class << self
    # Install +keys+/+current_version+ for the rest of +file+, recording the
    # config it displaces the first time that file calls in.
    def install(keys, current_version, file)
      unless owns_baseline?(file)
        @baseline = baseline_for(file)
        @baseline_file = file
      end

      apply(keys, current_version)
    end

    # Put back the config #install displaced.
    def restore
      # A nil baseline means the file only ever set the config inline, inside
      # test cases. Falling back to the suite-wide default of "no keys" is what
      # those files need and is never wrong: nothing is left installed either way.
      baseline = @baseline || Snapshot.new(nil, nil)
      @baseline = nil
      @baseline_file = nil
      apply(baseline.keys, baseline.version)
    end

    # Install +keys+/+current_version+ for the duration of the block. Unlike
    # #install this always restores what it displaced, so it nests.
    def scoped(keys, current_version, file)
      displaced = snapshot # first, so the ensure below always has one
      warn_on_leaked_config(file) if leaked? && !owns_baseline?(file)

      apply(keys, current_version)
      yield
    ensure
      apply(displaced.keys, displaced.version)
    end

    private

    # True when +file+ is the one whose install is currently outstanding. A
    # second install from the same file must not re-baseline: a setup that
    # installs a keyring and then widens it still has to restore the config from
    # before the file, not the intermediate one.
    def owns_baseline?(file)
      !@baseline_file.nil? && @baseline_file == file
    end

    # What +file+ should be restored to when it finishes. Normally that is
    # whatever it displaces. But if the config is already populated with nobody
    # currently owning it, an earlier file either assigned it directly or forgot
    # its teardown -- so baseline to the empty keyring instead. That ends the
    # leak at this file rather than handing it on to the next one.
    def baseline_for(file)
      return snapshot unless leaked?

      warn_on_leaked_config(file)
      Snapshot.new(nil, nil)
    end

    def leaked?
      !(Familia.config.encryption_keys.nil? &&
        Familia.config.current_key_version.nil?)
    end

    def snapshot
      Snapshot.new(Familia.config.encryption_keys, Familia.config.current_key_version)
    end

    def apply(keys, version)
      Familia.config.encryption_keys = keys
      Familia.config.current_key_version = version
      wipe_derived_key_cache

      keys
    end

    # Derived keys are cached per fiber under version+context, not under the
    # master key they came from, so swapping the keyring without wiping the cache
    # can hand back a key derived from the keyring we just replaced.
    def wipe_derived_key_cache
      Familia::Encryption.clear_request_cache!

      # clear_request_cache! leaves the enabled flag `false`, but the suite's
      # pristine value is nil -- request_cache_try asserts that an untouched
      # fiber reads nil, not false. Put both fiber-locals fully back so installing
      # a keyring never counts as having opted into (and out of) the cache.
      Fiber[:familia_request_cache] = nil
      Fiber[:familia_request_cache_enabled] = nil
    end

    # The config is populated and no file currently owns it: some earlier file
    # assigned it directly, or forgot its teardown. Say so loudly -- that leak is
    # what these helpers exist to prevent, and it is invisible otherwise.
    def warn_on_leaked_config(file)
      warn '[tryouts] Familia.config encryption keys were already installed on ' \
           "entry to #{file}: an earlier file set them without restoring. " \
           'See try/support/helpers/encryption_config.rb (issue #363).'
    end
  end
end

# Install encryption keys for the current try file. Pair with
# #clear_test_encryption_keys in the file's teardown.
#
# The caller's path is what scopes the override to one file, so it is captured
# here rather than inside the module: under the tryouts runner every section of
# a file evaluates with that file as its source location.
def set_test_encryption_keys(keys, current_version: nil)
  TestEncryptionConfig.install(keys, current_version, caller_locations(1, 1)&.first&.path)
end

# Restore the encryption config displaced by #set_test_encryption_keys, or clear
# it outright if the file only ever set the config inline.
def clear_test_encryption_keys
  TestEncryptionConfig.restore
end

# Install encryption keys for the duration of a block, restoring on exit.
def with_test_encryption_keys(keys, current_version: nil, &block)
  TestEncryptionConfig.scoped(keys, current_version, caller_locations(1, 1)&.first&.path, &block)
end
