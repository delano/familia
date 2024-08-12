# rubocop:disable all
#
module Familia::Features
  module ApiVersion

    def apiversion(val = nil, &blk)
      if blk.nil?
        @apiversion = val if val
      else
        tmp = @apiversion
        @apiversion = val
        yield
        @apiversion = tmp
      end
      @apiversion
    end

  end
end
