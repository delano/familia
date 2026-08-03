# lib/familia/encryption/providers/blake2b_personalization.rb
#
# frozen_string_literal: true

module Familia
  module Encryption
    module Providers
      # Shared BLAKE2b personalization handling for the XChaCha20-Poly1305
      # providers (XChaCha20Poly1305Provider and its unregistered prototype
      # sibling SecureXChaCha20Poly1305Provider). Both providers include this
      # module so the personalization rotation logic exists exactly once --
      # the two files have drifted apart before (#250, #356).
      #
      # Mirrors the AES-GCM HKDF salt rotation design from #310/#311:
      # encryption uses the fail-closed current value, decryption walks a
      # permissive candidate list ending with the pre-rotation default.
      # See issue #333.
      module Blake2bPersonalization
        # The built-in personalization every deployment shipped with before
        # rotation support (#333). Retained ONLY as a decryption fallback (see
        # #personalizations) so data written under the default stays readable
        # after an operator rotates to a deployment-specific value. Never used
        # to encrypt new data once the config no longer resolves to it.
        LEGACY_PERSONALIZATION = 'FamilialMatters'

        # Ordered list of personalization strings to consider when DECRYPTING,
        # current first.
        #
        # Decryption walks this list until the authenticated decrypt succeeds,
        # so it is intentionally permissive: it reads the raw config value (not
        # #current_personalization, which raises) and ends with the built-in
        # default, so existing ciphertext stays readable even if the current
        # config is broken. A wrong personalization derives a different key and
        # fails Poly1305 authentication cleanly, so iterating never yields a
        # false positive.
        #
        # The filter is load-bearing, not cosmetic: a candidate that is not a
        # String, is blank, contains null bytes, or exceeds BLAKE2b's 16-byte
        # personalization limit would raise mid-walk (EncryptionError or
        # RbNaCl::LengthError) and abort the remaining candidates, so such
        # entries are dropped here instead of attempted.
        #
        # ENCRYPTION does NOT use this list's head -- see
        # #current_personalization, which fails closed rather than silently
        # encrypting under a fallback value.
        #
        # @return [Array<String>] Valid candidates, current first, deduplicated
        def personalizations
          current = Familia.config.encryption_personalization
          history = Familia.config.encryption_personalization_history
          [current, *history, LEGACY_PERSONALIZATION].select do |candidate|
            candidate.is_a?(String) && !candidate.empty? &&
              !candidate.include?("\0") && candidate.bytesize <= 16
          end.uniq
        end

        # The personalization string used to ENCRYPT new data.
        #
        # Unlike #personalizations (the permissive decryption candidate list),
        # this fails CLOSED. A nil or empty encryption_personalization is a
        # misconfiguration -- and the raw attr_writer can set one, bypassing
        # the reader's guards -- so refuse rather than silently deriving under
        # a fallback (#311). Null-byte padding to BLAKE2b's 16 bytes happens at
        # derive time (ljust in #derive_key), not here.
        #
        # @return [String] The validated current personalization string
        # @raise [EncryptionError] When the configured value is invalid
        def current_personalization
          validate_personalization!(Familia.config.encryption_personalization)
        end

        private

        # Fail-closed validation for a single personalization value, applied to
        # both the configured current value (#current_personalization) and any
        # explicitly-passed `personal:` candidate in #derive_key. With
        # #personalizations filtering the decrypt walk, this is defense in
        # depth for direct callers.
        #
        # @param raw_personal [Object] Candidate personalization value
        # @return [String] The value, unchanged, when valid
        # @raise [EncryptionError] When the value is invalid
        def validate_personalization!(raw_personal)
          # Fail closed on a missing personalization rather than crashing with a
          # NoMethodError on nil (#311): a blank value gives no domain separation,
          # and the raw attr_writer can set nil/'' past the reader's guards.
          unless raw_personal.is_a?(String) && !raw_personal.empty?
            raise EncryptionError, 'encryption_personalization must be a non-empty string for key derivation'
          end
          raise EncryptionError, 'Personalization string must not contain null bytes' if raw_personal.include?("\0")
          if raw_personal.bytesize > 16
            raise EncryptionError,
                  'Personalization string cannot exceed 16 bytes (BLAKE2b personalization limit)'
          end

          raw_personal
        end
      end
    end
  end
end
