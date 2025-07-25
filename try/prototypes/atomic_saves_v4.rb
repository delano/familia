# try/prototypes/atomic_saves_v4.rb

class BankAccount < Familia::Horreum
  class_sorted_set :relatable_object_ids

  identifier_field :account_number
  field :account_number
  field :balance
  field :foreign_balance
  field :holder_name

  string :metadata  # A separate dbkey, to store JSON blog

  def init
    @account_number ||= SecureRandom.hex(8)
    @balance = @balance.to_f if @balance
    @foreign_balance = @foreign_balance.to_f if @foreign_balance
    @metadata = @metadata.is_a?(String) ? JSON.parse(@metadata) : @metadata
  end

  def balance
    @balance&.to_f
  end

  def withdraw(amount)
    raise "Insufficient funds" if balance < amount
    self.balance -= amount
  end

  def deposit(amount)
    # This is PURPOSE3, for complex updates for objects that already exist.
    self.transaction do
      self.balance += amount
      self.foreign_balance = balance * 1.25 # exchange rate
    end
  end

  def an_example_that_we_do_not_want
    # This is how multi worked in Familia before this project. This
    # is what we are trying to avoid by not using blocks. However,
    # it's not the block that is the issue; it's losing the object
    # oriented `self.fieldname = value` syntax and having to manually
    # resort to functional programming.
    dbclient.multi do |multi|
      multi.del(dbkey)
      # Also remove from the class-level values, :display_domains, :owners
      multi.zrem(V2::CustomDomain.values.dbkey, identifier)
      multi.hdel(V2::CustomDomain.display_domains.dbkey, display_domain)
      multi.hdel(V2::CustomDomain.owners.dbkey, display_domain)
      multi.del(brand.dbkey)
      multi.del(logo.dbkey)
      multi.del(icon.dbkey)
      unless customer.nil?
        multi.zrem(customer.custom_domains.dbkey, display_domain)
      end
    end
  end

  def metadata=(value)
    @metadata = value.is_a?(Hash) || value.is_a?(Array) ? JSON.generate(value) : value
  end

  class << self
    def create(account_number, holder_name, metadata = {})

      attrs = {
        account_number: account_number,
        balance: 0.0,
        holder_name: holder_name,
        metadata: metadata
      }

      # By convention, we would not write any code that runs on initialization
      # that has any database operations. However if we did, they would still work
      # the would just run immediately and not with the following transaction.
      accnt = new attrs

      Familia.transaction do

        # Inside this block, `accnt.dbclient` returns the open multi connection.
        #
        # Anything that calls database commands, will be queues on the multi
        # connection, like attr.metadata = {...}. So neither the main object
        # key or the separate `metadata` string key will update unless both
        # succeed. This is PURPOSE1.
        accnt.save

        # PROBLEM: what is returned here when we call accnt.class.dbclient? where
        # does a class level method like `add` get its db connection from then?
        #
        # This is PURPOSE2, a major reason for implementing transactions. We want
        # to prevent our relatable_object_ids index from being updated if the
        # account save fails.
        add accnt

        # Transaction method returns the block return
        accnt
      end
    end

    def add(accnt)
      relatable_object_ids.add Time.now.to_f, accnt.identifier
    end
  end
end
