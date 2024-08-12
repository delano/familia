# rubocop:disable all

require 'securerandom'

module Familia

  module Utils

    def debug?
      @debug == true
    end

    def generate_id
      input = SecureRandom.hex(32)  # 16=128 bits, 32=256 bits
      Digest::SHA256.hexdigest(input).to_i(16).to_s(36) # base-36 encoding
    end

    def join(*val)
      val.join(Familia.delim)
    end

    def split(val)
      val.split(Familia.delim)
    end

    def now(name = Time.now)
      name.utc.to_i
    end

    # A quantized timestamp
    # e.g. 12:32 -> 12:30
    #
    def qnow(quantum = 10.minutes, now = Familia.now)
      rounded = now - (now % quantum)
      Time.at(rounded).utc.to_i
    end

    def qstamp(quantum = nil, pattern = nil, now = Familia.now)
      quantum ||= ttl || 10.minutes
      pattern ||= '%H%M'
      rounded = now - (now % quantum)
      Time.at(rounded).utc.strftime(pattern)
    end

  end
end
