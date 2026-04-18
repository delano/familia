require_relative '../support/helpers/test_helpers'
require 'base64'

Familia.debug = false

# Coverage extensions for atomic_write across data type variants that the
# main atomic_write_try.rb suite does not exercise directly:
#   (a) Encrypted fields (features/encrypted_fields)
#   (b) JsonStringKey (json_string DSL) participating in the MULTI
#   (c) StringKey (string DSL) raw-string operations like INCR/APPEND inside MULTI

# Configure encryption keys for the encrypted_field fixtures. Mirrors the
# pattern used in try/features/encrypted_fields/encrypted_fields_core_try.rb.
test_keys = { v1: Base64.strict_encode64('a' * 32) }
Familia.config.encryption_keys = test_keys
Familia.config.current_key_version = :v1

# (a) Horreum with encrypted_field + a regular collection. Exercises the
# encryption-on-assignment path inside an atomic_write block. The plaintext
# is encrypted in-memory at assignment time (producing a ConcealedString);
# persist_to_storage queues the resulting JSON ciphertext via HMSET inside
# the MULTI alongside the SADDs for the tags set.
class AtomicWriteEncryptedPlan < Familia::Horreum
  feature :encrypted_fields
  identifier_field :planid
  field :planid
  field :name
  encrypted_field :secret
  set :tags
end

# (b) Horreum with a JsonStringKey (json_string DSL). JsonStringKey lives on
# its own dbkey; mutations are immediate, so inside atomic_write they auto-
# route into the open MULTI via Fiber[:familia_transaction].
class AtomicWriteJsonPlan < Familia::Horreum
  identifier_field :planid
  field :planid
  field :name
  json_string :config
end

# (c) Horreum with a raw StringKey (string DSL). StringKey supports INCR /
# DECR / APPEND because its serialize_value uses raw .to_s rather than JSON.
class AtomicWriteStringPlan < Familia::Horreum
  identifier_field :planid
  field :planid
  field :name
  string :counter
end

# Clean slate
AtomicWriteEncryptedPlan.instances.clear rescue nil
AtomicWriteEncryptedPlan.all.each(&:destroy!) rescue nil
AtomicWriteJsonPlan.instances.clear rescue nil
AtomicWriteJsonPlan.all.each(&:destroy!) rescue nil
AtomicWriteStringPlan.instances.clear rescue nil
AtomicWriteStringPlan.all.each(&:destroy!) rescue nil

## (a) atomic_write commits an encrypted_field assignment and a set mutation atomically
@enc_a = AtomicWriteEncryptedPlan.new(planid: 'aw_enc_a', name: 'EncTest')
@enc_a.atomic_write do
  @enc_a.secret = 'classified'
  @enc_a.tags.add('alpha')
  @enc_a.tags.add('beta')
end
@enc_a_reloaded = AtomicWriteEncryptedPlan.find_by_id('aw_enc_a')
@revealed = @enc_a_reloaded.secret.reveal { |plain| plain }
[@enc_a_reloaded.name, @revealed, @enc_a_reloaded.tags.members.sort]
#=> ['EncTest', 'classified', ['alpha', 'beta']]

## (a) encrypted_field updates inside atomic_write replace prior ciphertext
@enc_b = AtomicWriteEncryptedPlan.new(planid: 'aw_enc_b', name: 'EncUpdate')
@enc_b.secret = 'first'
@enc_b.save
@enc_b.atomic_write do
  @enc_b.secret = 'second'
  @enc_b.tags.add('gamma')
end
@enc_b_reloaded = AtomicWriteEncryptedPlan.find_by_id('aw_enc_b')
@revealed_b = @enc_b_reloaded.secret.reveal { |plain| plain }
[@revealed_b, @enc_b_reloaded.tags.members]
#=> ['second', ['gamma']]

## (b) atomic_write writes a Hash to a json_string and commits with EXEC
@json_a = AtomicWriteJsonPlan.new(planid: 'aw_json_a', name: 'JsonTest')
@json_a.atomic_write do
  @json_a.config.value = { 'theme' => 'dark', 'level' => 7, 'beta' => true }
end
@json_a_reloaded = AtomicWriteJsonPlan.find_by_id('aw_json_a')
@json_a_reloaded.config.value
#=> {"theme"=>"dark", "level"=>7, "beta"=>true}

## (b) atomic_write overwrites an existing json_string value
@json_b = AtomicWriteJsonPlan.new(planid: 'aw_json_b', name: 'JsonOverwrite')
@json_b.config.value = { 'before' => 1 }
@json_b.atomic_write do
  @json_b.config.value = { 'after' => 2, 'nested' => [1, 2, 3] }
end
@json_b_reloaded = AtomicWriteJsonPlan.find_by_id('aw_json_b')
@json_b_reloaded.config.value
#=> {"after"=>2, "nested"=>[1, 2, 3]}

## (c) atomic_write INCR on a raw StringKey commits the increment
@str_a = AtomicWriteStringPlan.new(planid: 'aw_str_a', name: 'CounterTest')
@str_a.counter.value = '10'  # raw string; StringKey stores as "10"
@str_a.atomic_write do
  @str_a.counter.incr
  @str_a.counter.incr
  @str_a.counter.incr
end
@str_a_reloaded = AtomicWriteStringPlan.find_by_id('aw_str_a')
@str_a_reloaded.counter.value.to_i
#=> 13

## (c) StringKey mutation inside atomic_write returns a Redis::Future (uninspectable until EXEC)
## Documents that operations queued inside MULTI return Future objects -- callers must NOT
## inspect them until after the block completes (and even then the values come from the
## MultiResult, not the Future itself).
@str_b = AtomicWriteStringPlan.new(planid: 'aw_str_b', name: 'FutureCheck')
@str_b.counter.value = '0'
@inside_return_value = nil
@str_b.atomic_write do
  @inside_return_value = @str_b.counter.incr
end
@inside_return_value.is_a?(Redis::Future)
#=> true

## (c) atomic_write APPEND on a StringKey commits the appended bytes
@str_c = AtomicWriteStringPlan.new(planid: 'aw_str_c', name: 'AppendTest')
@str_c.counter.value = 'foo'
@str_c.atomic_write do
  @str_c.counter.append('-bar')
  @str_c.counter.append('-baz')
end
@str_c_reloaded = AtomicWriteStringPlan.find_by_id('aw_str_c')
@str_c_reloaded.counter.value
#=> 'foo-bar-baz'

# Cleanup. Reset encryption config so it does not bleed into adjacent test
# files under the default shared-context tryouts runner.
AtomicWriteEncryptedPlan.instances.clear rescue nil
AtomicWriteEncryptedPlan.all.each(&:destroy!) rescue nil
AtomicWriteJsonPlan.instances.clear rescue nil
AtomicWriteJsonPlan.all.each(&:destroy!) rescue nil
AtomicWriteStringPlan.instances.clear rescue nil
AtomicWriteStringPlan.all.each(&:destroy!) rescue nil
Familia.config.encryption_keys = nil
Familia.config.current_key_version = nil
