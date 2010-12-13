require 'storable'

class Bone < Storable
  include Familia
  field :token
  field :name
  def id
    [token, name].join(':')
  end
  list   :owners
  set    :tags
  zset   :metrics
  hash   :props
  string :value, :default => "GREAT!"
end


class Session < Storable
  include Familia
  index :sessid
  field :sessid
  field :custid
  include Familia::Stamps
  ttl 60 # seconds to live
end


class Customer < Storable
  include Familia
  index :custid
  field :custid => Symbol
  field :name
  include Familia::Stamps
  # string :object, :class => self  # example of manual override
  class_list :customers, :suffix => []
  class_string :message
end

