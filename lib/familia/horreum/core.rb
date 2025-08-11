# lib/familia/horreum/core.rb

require_relative 'core/database_commands'
require_relative 'core/serialization'
require_relative 'core/connection'
require_relative 'core/utils'

module Familia
  class Horreum
    module Core
      include Familia::Horreum::DatabaseCommands
      include Familia::Horreum::Serialization
      # include for instance methods after it's loaded. Note that Horreum::Utils
      # are also included and at one time also has a uri method. This connection
      # module is also extended for the class level methods. It will require some
      # disambiguation at some point.
      include Familia::Horreum::Connection
      include Familia::Horreum::Utils
    end
  end
end
