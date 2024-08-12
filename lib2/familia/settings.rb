# rubocop:disable all

module Familia

  @delim = ':'
  @suffix = :object

  module Settings

    attr_accessor :delim, :suffix

    # We define this do-nothing method because it reads better
    # than simply Familia.suffix in some contexts.
    def default_suffix
      suffix
    end

  end
end
