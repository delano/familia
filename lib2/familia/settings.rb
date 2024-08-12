# rubocop:disable all

module Familia

  @delim = ':'
  @prefix = nil
  @suffix = :object
  @ttl = nil
  @db = nil

  module Settings

    attr_accessor :delim, :suffix, :ttl, :db, :prefix

    # We define this do-nothing method because it reads better
    # than simply Familia.suffix in some contexts.
    def default_suffix
      suffix
    end

  end
end
