# lib/familia/data_type.rb
#
# frozen_string_literal: true

require_relative 'data_type/class_methods'
require_relative 'data_type/settings'
require_relative 'data_type/connection'
require_relative 'data_type/database_commands'
require_relative 'data_type/serialization'

# Familia
#
module Familia
  # DataType - Base class for Database data type wrappers
  #
  # This class provides common functionality for various Database data types
  # such as String, List, UnsortedSet, SortedSet, and HashKey.
  #
  # @abstract Subclass and implement Database data type specific methods
  class DataType
    include Familia::Base
    extend ClassMethods
    extend Familia::Features

    using Familia::Refinements::TimeLiterals

    @registered_types = {}
    @valid_options = %i[class parent default_expiration default logical_database dbkey dbclient suffix prefix].freeze
    @logical_database = nil

    feature :expiration
    feature :quantization

    class << self
      attr_reader :registered_types, :valid_options, :has_related_fields
    end

    # +keystring+: If parent is set, this will be used as the suffix
    # for dbkey. Otherwise this becomes the value of the key.
    # If this is an Array, the elements will be joined.
    #
    # Options:
    #
    # :class => A class that responds to Familia.load_method and
    # Familia.dump_method. These will be used when loading and
    # saving data from/to the database to unmarshal/marshal the class.
    #
    # :parent => The Familia object that this datatype object belongs
    # to. This can be a class that includes Familia or an instance.
    #
    # :default_expiration => the time to live in seconds. When not nil, this will
    # set the default expiration for this dbkey whenever #save is called.
    # You can also call it explicitly via #update_expiration.
    #
    # :default => the default value (String-only)
    #
    # :dbkey => a hardcoded key to use instead of the deriving the from
    # the name and parent (e.g. a derived key: customer:custid:secret_counter).
    #
    # :suffix => the suffix to use for the key (e.g. 'scores' in customer:custid:scores).
    # :prefix => the prefix to use for the key (e.g. 'customer' in customer:custid:scores).
    #
    # Connection precendence: uses the database connection of the parent or the
    # value of opts[:dbclient] or Familia.dbclient (in that order).
    def initialize(keystring, opts = {})
      @keystring = keystring
      @keystring = @keystring.join(Familia.delim) if @keystring.is_a?(Array)

      # Remove all keys from the opts that are not in the allowed list
      @opts = DataType.valid_keys_only(opts || {})

      # Apply the options to instance method setters of the same name
      @opts.each do |k, v|
        send(:"#{k}=", v) if respond_to? :"#{k}="
      end

      init if respond_to? :init
    end

    include Settings
    include Connection
    include DatabaseCommands
    include Serialization
  end

  require_relative 'data_type/types/listkey'
  require_relative 'data_type/types/unsorted_set'
  require_relative 'data_type/types/sorted_set'
  require_relative 'data_type/types/hashkey'
  require_relative 'data_type/types/stringkey'
  require_relative 'data_type/types/json_stringkey'
end
