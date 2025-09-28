# lib/familia/connection/base_handler.rb

# Familia
#
# A family warehouse for your keystore data.
#
module Familia
  module Connection
    # Connection handler base class for Chain of Responsibility pattern
    class BaseConnectionHandler
      def initialize(familia_module)
        @familia = familia_module
      end

      def try_connection(uri)
        raise NotImplementedError, 'Subclasses must implement try_connection'
      end
    end
  end
end
