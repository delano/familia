# rubocop:disable all
#
module Familia

  @uri = URI.parse 'redis://127.0.0.1'
  @redis_clients = {}

  module Connection

    attr_reader :redis_clients, :uri

    def connect(uri = nil)
      uri &&= URI.parse uri if uri.is_a?(String)
      uri ||= Familia.uri

      conf = uri.conf

      #Familia.trace(:CONNECT, redis, conf.inspect, caller[0..3])

      redis = Redis.new conf

      @redis_clients[uri.serverid] = redis
    end

    def redis(uri = nil)
      uri &&= URI.parse(uri)
      uri ||= Familia.uri

      connect(uri) unless @redis_clients[uri.serverid]
      @redis_clients[uri.serverid]
    end

    def uri=(v)
      v = URI.parse v unless URI === v
      @uri = v
    end

  end
end
