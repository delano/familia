# try/edge_cases/legacy_data_detection/deserialize_value_override_try.rb
#
# frozen_string_literal: true

# Horreum#deserialize_value takes dbkey:, the key a value was read from, and
# names it in the log entry for a value that is not JSON. A model can
# override deserialize_value. An override with the signature from before
# dbkey: was added, (val, symbolize: false, field_name: nil), raises
# ArgumentError when given dbkey:. So the hydration paths pass dbkey: only
# when every deserialize_value up the super chain takes it, by name or
# through **.

require_relative '../../support/helpers/test_helpers'
require 'stringio'

# Models and helpers for this file.
module DeserializeValueOverrideTry
  # Override with the signature from before dbkey: was added.
  class PreDbkey < Familia::Horreum
    prefix :desval_override_pre
    identifier_field :pid
    field :pid
    field :count

    def self.calls
      @calls ||= []
    end

    def deserialize_value(val, symbolize: false, field_name: nil)
      self.class.calls << field_name.to_s
      super
    end
  end

  # Override that names dbkey:.
  class NamedDbkey < Familia::Horreum
    prefix :desval_override_named
    identifier_field :pid
    field :pid
    field :count

    def self.dbkeys
      @dbkeys ||= []
    end

    def deserialize_value(val, symbolize: false, field_name: nil, dbkey: nil)
      self.class.dbkeys << dbkey
      super
    end
  end

  # Override that takes **.
  class Kwargs < Familia::Horreum
    prefix :desval_override_kwargs
    identifier_field :pid
    field :pid
    field :count

    def self.dbkeys
      @dbkeys ||= []
    end

    def deserialize_value(val, **opts)
      self.class.dbkeys << opts.fetch(:dbkey, :absent)
      super
    end
  end

  # Takes ** and hands it to super.
  module KwargsWrapper
    def deserialize_value(val, **opts)
      super
    end
  end

  # KwargsWrapper prepended over the inherited PreDbkey override.
  class Wrapped < PreDbkey
    prefix :desval_override_wrapped
    prepend KwargsWrapper
  end

  # The hydration paths that read a key.
  KEYED_PATHS = %i[find_by_id find_by_dbkey load_multi load_multi_by_keys refresh! storage_inspect].freeze

  # The dbkey: values the override received on each path, without repeats.
  def self.dbkeys_by_path(klass, record)
    paths = {
      find_by_id: -> { klass.find_by_id(record.identifier) },
      find_by_dbkey: -> { klass.find_by_dbkey(record.dbkey) },
      load_multi: -> { klass.load_multi([record.identifier]) },
      load_multi_by_keys: -> { klass.load_multi_by_keys([record.dbkey]) },
      refresh!: -> { record.refresh! },
      storage_inspect: -> { klass.storage_inspect(record.identifier) },
    }
    paths.transform_values do |path|
      klass.dbkeys.clear
      path.call
      klass.dbkeys.uniq
    end
  end

  # The log output written while the block runs.
  def self.log_during
    io = StringIO.new
    original = Familia.logger
    Familia.logger = Familia::FamiliaLogger.new(io)
    begin
      yield
    ensure
      Familia.logger = original
    end
    io.string
  end
end

@pre = DeserializeValueOverrideTry::PreDbkey.new(pid: 'pre1', count: 5)
@pre.save
@named = DeserializeValueOverrideTry::NamedDbkey.new(pid: 'named1', count: 5)
@named.save
@kwargs = DeserializeValueOverrideTry::Kwargs.new(pid: 'kwargs1', count: 5)
@kwargs.save
@wrapped = DeserializeValueOverrideTry::Wrapped.new(pid: 'wrapped1', count: 5)
@wrapped.save

## find_by_id loads through an override without dbkey:
DeserializeValueOverrideTry::PreDbkey.calls.clear
@loaded = DeserializeValueOverrideTry::PreDbkey.find_by_id('pre1')
[@loaded.count, DeserializeValueOverrideTry::PreDbkey.calls.sort]
#=> [5, %w[count pid]]

## find_by_dbkey loads through an override without dbkey:
DeserializeValueOverrideTry::PreDbkey.find_by_dbkey(@pre.dbkey).count
#=> 5

## load_multi loads through an override without dbkey:
DeserializeValueOverrideTry::PreDbkey.load_multi(['pre1']).map(&:count)
#=> [5]

## load_multi_by_keys loads through an override without dbkey:
DeserializeValueOverrideTry::PreDbkey.load_multi_by_keys([@pre.dbkey]).map(&:count)
#=> [5]

## refresh! loads through an override without dbkey:
@pre.count = 9
@pre.refresh!
@pre.count
#=> 5

## naive_refresh deserializes through an override without dbkey:
@pre.naive_refresh(count: '7')
@pre.count
#=> 7

## storage_inspect decodes through an override without dbkey:
DeserializeValueOverrideTry::PreDbkey.storage_inspect('pre1').transform_values { |entry| entry[:decoded] }
#=> { 'pid' => 'pre1', 'count' => 5 }

## a value that is not JSON loads through an override without dbkey:, logged without the key
Familia.dbclient.hset(@pre.dbkey, 'count', 'plain-legacy')
@log = DeserializeValueOverrideTry.log_during do
  @loaded = DeserializeValueOverrideTry::PreDbkey.find_by_id('pre1')
end
[@loaded.count, @log[/Legacy plain string in \S+PreDbkey#count \(([^)]*)\)/, 1]]
#=> ['plain-legacy', 'no dbkey']

## an override that names dbkey: receives the key each hydration path read
DeserializeValueOverrideTry.dbkeys_by_path(DeserializeValueOverrideTry::NamedDbkey, @named)
#=> DeserializeValueOverrideTry::KEYED_PATHS.to_h { |path| [path, [@named.dbkey]] }

## an override that names dbkey: logs the key read for a value that is not JSON
Familia.dbclient.hset(@named.dbkey, 'count', 'plain-legacy')
@log = DeserializeValueOverrideTry.log_during do
  DeserializeValueOverrideTry::NamedDbkey.find_by_id('named1')
end
@log[/Legacy plain string in \S+#count \(([^)]*)\)/, 1]
#=> @named.dbkey

## an override that takes ** receives the key each hydration path read
DeserializeValueOverrideTry.dbkeys_by_path(DeserializeValueOverrideTry::Kwargs, @kwargs)
#=> DeserializeValueOverrideTry::KEYED_PATHS.to_h { |path| [path, [@kwargs.dbkey]] }

## naive_refresh reads no key, so it passes no dbkey:
DeserializeValueOverrideTry::Kwargs.dbkeys.clear
@kwargs.naive_refresh(count: '7')
[@kwargs.count, DeserializeValueOverrideTry::Kwargs.dbkeys.uniq]
#=> [7, [:absent]]

## a prepended override that takes ** over an override without dbkey: loads
[
  DeserializeValueOverrideTry::Wrapped.find_by_id('wrapped1').count,
  DeserializeValueOverrideTry::Wrapped.load_multi_by_keys([@wrapped.dbkey]).map(&:count),
  DeserializeValueOverrideTry::Wrapped.storage_inspect('wrapped1')['count'][:decoded],
]
#=> [5, [5], 5]

## a singleton override without dbkey: on an object whose class takes it refreshes
@single = DeserializeValueOverrideTry::NamedDbkey.find_by_id('named1')
def @single.deserialize_value(val, symbolize: false, field_name: nil)
  super
end
Familia.dbclient.hset(@named.dbkey, 'count', '11')
@single.refresh!
@single.count
#=> 11

delete_test_dbkeys(
  DeserializeValueOverrideTry::PreDbkey,
  DeserializeValueOverrideTry::NamedDbkey,
  DeserializeValueOverrideTry::Kwargs,
  DeserializeValueOverrideTry::Wrapped,
)
