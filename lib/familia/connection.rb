# lib/familia/connection.rb

require_relative 'connection/handlers'
require_relative 'connection/middleware'
require_relative 'connection/operations'
require_relative 'connection/individual_command_proxy'
require_relative 'connection/transaction_core'

# Familia
#
# A family warehouse for your keystore data.
#
module Familia
  @uri = URI.parse 'redis://127.0.0.1:6379'
  @middleware_registered = false
  @middleware_version = 0

  # The Connection module provides Database connection management for Familia.
  # It allows easy setup and access to Database clients across different URIs
  # with robust connection pooling for thread safety.
  module Connection
    # @return [URI] The default URI for Database connections
    attr_reader :uri

    # @return [Proc] A callable that provides Database connections
    # The provider should accept a URI string and return a Redis connection
    # already connected to the correct database specified in the URI.
    #
    # @example Setting a connection provider
    #   Familia.connection_provider = ->(uri) do
    #     pool = ConnectionPool.new { Redis.new(url: uri) }
    #     pool.with { |conn| conn }
    #   end
    attr_reader :connection_provider

    # Sets the connection provider and bumps middleware version
    def connection_provider=(provider)
      @connection_provider = provider
      increment_middleware_version! if provider
      @connection_chain = nil # Force rebuild of chain
    end

    # Sets the default URI for Database connections.
    #
    # NOTE: uri is not a property of the Settings module b/c it's not
    # configured in class defintions like default_expiration or logical DB index.
    #
    # @param uri [String, URI] The new default URI
    # @example Familia.uri = 'redis://localhost:6379'
    def uri=(uri)
      @uri = normalize_uri(uri)
    end
    alias url uri
    alias url= uri=

    # Creates a new Database connection instance.
    #
    # This method always creates a fresh connection and does not use caching.
    # Each call returns a new Redis client instance that you are responsible
    # for managing and closing when done.
    #
    # @param uri [String, URI, nil] The URI of the Database server to connect to.
    #   If nil, uses the default URI from Familia.uri.
    # @return [Redis] A new Database client connection.
    # @raise [ArgumentError] If no URI is specified.
    #
    # @example Creating a new connection
    #   client = Familia.create_dbclient('redis://localhost:6379')
    #   client.ping
    #   client.close
    #
    def create_dbclient(uri = nil)
      parsed_uri = normalize_uri(uri)

      # Register middleware only once, globally
      register_middleware_once

      Redis.new(parsed_uri.conf)
    end
    alias connect create_dbclient # backwards compatibility
    alias isolated_dbclient create_dbclient # matches with_isolated_dbclient api

    # Retrieves a Database connection using the Chain of Responsibility pattern.
    # Handles DB selection automatically based on the URI.
    #
    # @return [Redis] The Database client for the specified URI
    # @example Familia.dbclient('redis://localhost:6379/1')
    #   Familia.dbclient(2)  # Use DB 2 with default server
    def dbclient(uri = nil)
      @connection_chain ||= build_connection_chain
      @connection_chain.handle(uri)
    end

    # Builds the connection chain with handlers in priority order
    def build_connection_chain
      ResponsibilityChain.new
        .add_handler(Familia::Connection::FiberTransactionHandler.new)
        .add_handler(FiberConnectionHandler.new)
        .add_handler(ProviderConnectionHandler.new)
        .add_handler(CreateConnectionHandler.new)
    end

    # Normalizes various URI formats to a consistent URI object
    # Made public so handlers can use it
    def normalize_uri(uri)
      case uri
      when Integer
        new_uri = Familia.uri.dup
        new_uri.db = uri
        new_uri
      when ->(obj) { obj.is_a?(String) || obj.instance_of?(::String) }
        URI.parse(uri)
      when URI
        uri
      when nil
        Familia.uri
      else
        raise ArgumentError, "Invalid URI type: #{uri.class.name}"
      end
    end

    # Extend self with submodules to make their methods available as module methods
    include Familia::Connection::Middleware
    include Familia::Connection::Operations
  end
end
