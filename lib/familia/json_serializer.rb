# lib/familia/json_serializer.rb

module Familia
  # JsonSerializer provides a high-performance JSON interface using OJ
  #
  # This module wraps OJ with a clean API that can be easily swapped out
  # or benchmarked against other JSON implementations. Uses OJ's :strict
  # mode for RFC 7159 compliant JSON output.
  #
  # @example Basic usage
  #   data = { name: 'test', value: 123 }
  #   json = Familia::JsonSerializer.dump(data)
  #   parsed = Familia::JsonSerializer.parse(json, symbolize_names: true)
  #
  module JsonSerializer
    class << self
      # Parse JSON string into Ruby objects
      #
      # @param source [String] JSON string to parse
      # @param opts [Hash] parsing options
      # @option opts [Boolean] :symbolize_names convert hash keys to symbols
      # @return [Object] parsed Ruby object
      # @raise [SerializerError] if JSON is malformed
      def parse(source, opts = {})
        return nil if source.nil? || source == ''

        symbolize_names = opts[:symbolize_names] || opts['symbolize_names']

        if symbolize_names
          Oj.load(source, mode: :strict, symbol_keys: true)
        else
          Oj.load(source, mode: :strict)
        end
      rescue Oj::ParseError, Oj::Error, EncodingError => e
        raise SerializerError, e.message
      end

      # Serialize Ruby object to JSON string
      #
      # @param obj [Object] Ruby object to serialize
      # @return [String] JSON string
      def dump(obj)
        Oj.dump(obj, mode: :strict)
      rescue Oj::Error, TypeError, EncodingError => e
        raise SerializerError, e.message
      end

      # Alias for dump for JSON gem compatibility
      #
      # @param obj [Object] Ruby object to serialize
      # @return [String] JSON string
      def generate(obj)
        Oj.dump(obj, mode: :strict)
      rescue Oj::Error, TypeError, EncodingError => e
        raise SerializerError, e.message
      end

      # Serialize Ruby object to pretty-formatted JSON string
      #
      # @param obj [Object] Ruby object to serialize
      # @return [String] pretty-formatted JSON string
      def pretty_generate(obj)
        Oj.dump(obj, mode: :strict, indent: 2)
      rescue Oj::Error, TypeError, EncodingError => e
        raise SerializerError, e.message
      end
    end
  end
end
