# lib/familia/encryption/strict_base64.rb
#
# frozen_string_literal: true

module Familia
  module Encryption
    # Strict Base64 for encryption keys and envelope fields: no line feeds on
    # encode, and decode rejects anything that is not strict Base64.
    #
    # Core Ruby's Array#pack and String#unpack1 with the 'm0' directive do
    # this, so familia does not need the base64 gem. The base64 library that
    # ships with Ruby 3.2 and 3.3, and base64 gem versions 0.2.0 and 0.3.0,
    # implement their strict methods with the same calls:
    #
    #   def strict_encode64(bin)
    #     [bin].pack("m0")
    #   end
    #
    #   def strict_decode64(str)
    #     str.unpack1("m0")
    #   end
    #
    # @api private
    module StrictBase64
      module_function

      # @param bytes [String] binary data
      # @return [String] Base64 text without line feeds
      def encode(bytes)
        [bytes].pack('m0')
      end

      # @param text [String] strict Base64 text
      # @return [String] the decoded bytes, in ASCII-8BIT
      # @raise [ArgumentError] if text is not strict Base64
      def decode(text)
        text.unpack1('m0')
      end
    end
  end
end
