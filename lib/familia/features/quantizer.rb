# rubocop:disable all

module Familia::Features

  module Quantizer

    def qstamp(quantum = nil, pattern = nil, now = Familia.now)
      quantum ||= @opts[:quantize] || ttl || 10.minutes
      case quantum
      when Numeric
        # Handle numeric quantum (e.g., seconds, minutes)
      when Array
        quantum, pattern = *quantum
      end
      now ||= Familia.now
      rounded = now - (now % quantum)

      if pattern.nil?
        Time.at(rounded).utc.to_i # 3605 -> 3600
      else
        Time.at(rounded).utc.strftime(pattern || '%H%M') # 3605 -> '1:00'
      end

    end

  end
end
