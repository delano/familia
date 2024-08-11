# rubocop:disable all

module Familia

  module Utils

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

  end
end
