# rubocop:disable all
# frozen_string_literal: true


require 'securerandom'

module Familia
  def self.included(base)
    base.extend(ClassMethods)
  end

  module ClassMethods
    def index_fields(field_names)
      raise StandardError, 'Index already defined' if @index_field
      @index_fields = field_names
    end

    def index_field(field_name)
      index_fields([field_name])
    end

    def field(name)
      @fields ||= []
      @fields << name
      attr_accessor name
    end

    def fields
      @fields ||= []
    end
  end

  def initialize(**attributes)
    attributes.each do |key, value|
      send("#{key}=", value) if respond_to?("#{key}=")
    end

    # Set a default value for the index field if not provided
    index_field = self.class.index_field
    send("#{index_field}=", SecureRandom.uuid) if index_field && !send(index_field)
  end

  def to_h
    self.class.fields.each_with_object({}) do |field, hash|
      hash[field] = send(field)
    end
  end

  def to_a
    self.class.fields.map { |field| send(field) }
  end

end

class Session
  include Familia

  index :sessid
  field :sessid
  field :custid
end

# Usage example:
session = Session.new(custid: '12345')
puts session.sessid # Automatically generated UUID
puts session.custid # '12345'
puts session.to_h   # {:sessid=>"generated-uuid", :custid=>"12345"}
puts session.to_a   # ["generated-uuid", "12345"]
puts session[:custid] # "12345"
session[:custid] = '67890'
puts session.custid # "67890"



__END__

class Session
  include Familia
  index :sessid
  field :sessid
  field :custid
end

class Customer
  include Familia
  index :custid
  field :custid #=> Symbol
  field :name
  field :created

  field :reset_requested #=> Boolean
  hashkey :password_reset #=> Familia::HashKey
  list :sessions #=> Familia::List

  include Familia::Stamps
  # string :object, :class => self  # example of manual override
  class_list :customers, suffix: []
  class_string :message
end
