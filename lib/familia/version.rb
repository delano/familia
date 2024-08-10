
module Familia
  module VERSION
    def self.to_s
      load_config
      [@version[:MAJOR], @version[:MINOR], @version[:PATCH]].join('.')
    end
    alias inspect to_s
    def self.load_config
      require 'yaml'
      @version ||= YAML.load_file(File.join(FAMILIA_LIB_HOME, '..', 'VERSION.yml'))
    end
  end
end
