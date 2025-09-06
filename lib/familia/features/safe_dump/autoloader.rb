# lib/familia/features/safe_dump/autoloader.rb

module Familia
  module Features
    module SafeDump
      # SafeDump-specific autoloader that includes the base Autoloader
      # and provides feature-specific autoloading behavior.
      #
      # This module allows SafeDump to automatically load related files
      # based on the feature name, looking for patterns like:
      #   - features/safe_dump.rb
      #   - features/safe_dump/*.rb
      #   - features/safe_dump_*.rb
      #
      # Usage:
      #   class MyModel < Familia::Horreum
      #     feature :safe_dump
      #     # This will automatically load safe_dump-related files
      #   end
      #
      module Autoloader
        include Familia::Features::Autoloader::Loader
      end
    end
  end
end
