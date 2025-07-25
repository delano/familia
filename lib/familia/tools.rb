# lib/familia/tools.rb

module Familia
  module Tools
    extend self
    def move_keys(filter, source_uri, target_uri, &each_key)
      raise "Source and target are the same (#{target_uri})" if target_uri == source_uri

      Familia.connect target_uri
      source_keys = Familia.dbclient(source_uri).keys(filter)
      puts "Moving #{source_keys.size} keys from #{source_uri} to #{target_uri} (filter: #{filter})"
      source_keys.each_with_index do |key, idx|
        type = Familia.dbclient(source_uri).type key
        default_expiration = Familia.dbclient(source_uri).ttl key
        if source_uri.host == target_uri.host && source_uri.port == target_uri.port
          Familia.dbclient(source_uri).move key, target_uri.db
        else
          case type
          when 'string'
            Familia.dbclient(source_uri).get key
          when 'list'
            Familia.dbclient(source_uri).lrange key, 0, -1
          when 'set'
            Familia.dbclient(source_uri).smembers key
          else
            raise Familia::Problem, "unknown key type: #{type}"
          end
          raise 'Not implemented'
        end
        yield(idx, type, key, default_expiration) unless each_key.nil?
      end
    end

    # Use the return value from each_key as the new key name
    def rename(filter, source_uri, target_uri = nil, &each_key)
      target_uri ||= source_uri
      move_keys filter, source_uri, target_uri if source_uri != target_uri
      source_keys = Familia.dbclient(source_uri).keys(filter)
      puts "Renaming #{source_keys.size} keys from #{source_uri} (filter: #{filter})"
      source_keys.each_with_index do |key, idx|
        Familia.trace :RENAME1, Familia.dbclient(source_uri), "#{key}", ''
        type = Familia.dbclient(source_uri).type key
        default_expiration = Familia.dbclient(source_uri).ttl key
        newkey = yield(idx, type, key, default_expiration) unless each_key.nil?
        Familia.trace :RENAME2, Familia.dbclient(source_uri), "#{key} -> #{newkey}", caller(1..1).first
        Familia.dbclient(source_uri).renamenx key, newkey
      end
    end

    def get_any(keyname, uri = nil)
      type = Familia.dbclient(uri).type keyname
      case type
      when 'string'
        Familia.dbclient(uri).get keyname
      when 'list'
        Familia.dbclient(uri).lrange(keyname, 0, -1) || []
      when 'set'
        Familia.dbclient(uri).smembers(keyname) || []
      when 'zset'
        Familia.dbclient(uri).zrange(keyname, 0, -1) || []
      when 'hash'
        Familia.dbclient(uri).hgetall(keyname) || {}
      else
        nil
      end
    end
  end
end
