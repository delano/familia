# rubocop:disable all

require 'securerandom'

module Familia
  DIGEST_CLASS = Digest::SHA256

  module Utils

    def debug?
      @debug == true
    end

    def generate_id
      input = SecureRandom.hex(32)  # 16=128 bits, 32=256 bits
      Digest::SHA256.hexdigest(input).to_i(16).to_s(36) # base-36 encoding
    end

    def join(*val)
      val.compact.join(Familia.delim)
    end

    def split(val)
      val.split(Familia.delim)
    end

    def rediskey(*val)
      join(*val)
    end

    def redisuri(uri)
      generic_uri = URI.parse(uri.to_s)

      # Create a new URI::Redis object
      redis_uri = URI::Redis.build(
        scheme: generic_uri.scheme,
        userinfo: generic_uri.userinfo,
        host: generic_uri.host,
        port: generic_uri.port,
        path: generic_uri.path,
        query: generic_uri.query,
        fragment: generic_uri.fragment
      )

      redis_uri
    end

    def now(name = Time.now)
      name.utc.to_f
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

    def generate_sha_hash(elements)
      concatenated_string = Familia.join(elements)
      DIGEST_CLASS.hexdigest(concatenated_string)
    end

  end
end
