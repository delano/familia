# frozen_string_literal: true

require_relative 'migration/errors'
require_relative 'migration/script'
require_relative 'migration/registry'
require_relative 'migration/runner'
require_relative 'migration/base'
require_relative 'migration/model'
require_relative 'migration/pipeline'

module Familia
  module Migration
    class << self
      # Registered migration classes (populated by Base.inherited)
      def migrations
        @migrations ||= []
      end

      def migrations=(list)
        @migrations = list
      end

      # Configuration
      def config
        @config ||= Configuration.new
      end

      def configure
        yield config if block_given?
      end
    end

    class Configuration
      attr_accessor :migrations_key, :backup_ttl, :batch_size

      def initialize
        @migrations_key = 'familia:migrations'
        @backup_ttl = 86_400  # 24 hours
        @batch_size = 1000
      end
    end
  end
end
