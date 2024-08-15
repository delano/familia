# rubocop:disable all

require 'yaml'

module Familia
  module VERSION
    def self.to_s
      load_config
      version = [@version[:MAJOR], @version[:MINOR], @version[:PATCH]].join('.')
      version += "-#{@version[:PRE]}" if @version[:PRE]
      version
    end
    alias inspect to_s

    def self.version
      @version ||= load_config
      @version
    end

    def self.load_config
      version_file_path = File.join(__dir__, '..', '..', 'VERSION.yml')
      @version = YAML.load_file(version_file_path)
    end
  end
end
