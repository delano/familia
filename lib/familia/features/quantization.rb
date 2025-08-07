# lib/familia/features/quantization.rb

module Familia::Features

  module Quantization

    def self.included base
      Familia.ld "[#{base}] Loaded #{self}"
      base.extend ClassMethods
    end

    module ClassMethods
      # Generates a quantized timestamp based on the given parameters.
      #
      # @param quantum [Integer, Array, nil] The time quantum in seconds or an array of [quantum, pattern].
      # @param pattern [String, nil] The strftime pattern to format the timestamp.
      # @param now [Time, nil] The current time (default: Familia.now).
      # @return [Integer, String] A unix timestamp or formatted timestamp string.
      #
      # This method rounds the current time to the nearest quantum and optionally formats it
      # according to the given pattern. It's useful for creating time-based buckets
      # or keys with reduced granularity.
      #
      # @example
      #   User.qstamp(1.hour, '%Y%m%d%H')  # Returns a string like "2023060114" for 2:30 PM
      #   User.qstamp(10.minutes)  # Returns an integer timestamp rounded to the nearest 10 minutes
      #   User.qstamp([1.hour, '%Y%m%d%H'])  # Same as the first example
      #
      # @raise [ArgumentError] If quantum is not positive
      #
      def qstamp(quantum = nil, pattern: nil, time: nil)
        # Handle default values and array input
        if quantum.is_a?(Array)
          quantum, pattern = quantum
        end

        # Previously we erronously included `@opts.fetch(:quantize, nil)` in
        # the list of default values here, but @opts is for horreum instances
        # not at the class level. This method `qstamp` is part of the initial
        # definition for whatever horreum subclass we're in right now. That's
        # why default_expiration works (e.g. `class Plop; feature :quantization; default_expiration 90; end`).
        quantum ||= default_expiration || 10.minutes

        # Validate quantum
        unless quantum.is_a?(Numeric) && quantum.positive?
          raise ArgumentError, "Quantum must be positive (#{quantum.inspect} given)"
        end

        # Call Familia.qstamp with our processed parameters
        Familia.qstamp(quantum, pattern: pattern, time: time)
      end
    end

    def qstamp(quantum = nil, pattern: nil, time: nil)
      self.class.qstamp(quantum || self.class.default_expiration, pattern: pattern, time: time)
    end

    extend ClassMethods

    Familia::Base.add_feature self, :quantization
  end
end
