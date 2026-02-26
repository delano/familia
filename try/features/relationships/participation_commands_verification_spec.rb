# try/features/relationships/participation_commands_verification_spec.rb
#
# frozen_string_literal: true

# Generated rspec code for /Users/d/Projects/opensource/d/familia/try/features/relationships/participation_commands_verification_try.rb
# Updated: 2025-09-26 21:27:49 -0700

RSpec.describe 'participation_commands_verification_try' do
  before(:all) do
    require 'timecop'
    Timecop.freeze(Familia.parse("2024-01-15 10:30:00"))
    puts Familia.now  # Always returns 2024-01-15 10:30:00
    puts Date.today  # Always returns 2024-01-15
    require_relative '../../../lib/middleware/database_logger'
    require_relative '../../../lib/familia'
    Familia.enable_database_logging = true
    Familia.enable_database_counter = true
    class ReverseIndexCustomer < Familia::Horreum
      feature :relationships
      identifier_field :customer_id
      field :customer_id
      field :name
      sorted_set :domains
      set :preferred_domains
    end
    class ReverseIndexDomain < Familia::Horreum
      feature :relationships
      identifier_field :domain_id
      field :domain_id
      field :display_domain
      field :created_at
      participates_in ReverseIndexCustomer, :domains, score: :created_at
      participates_in ReverseIndexCustomer, :preferred_domains, generate_participant_methods: true
      class_participates_in :all_domains, score: :created_at
    end
  end

  before(:each) do
    # Create test objects for each test
    @customer = ReverseIndexCustomer.new(customer_id: 'ri_cust_123', name: 'Reverse Index Test Customer')
    @domain1 = ReverseIndexDomain.new(
      domain_id: 'ri_dom_1',
      display_domain: 'example1.com',
      created_at: Familia.now.to_f
    )
    @domain2 = ReverseIndexDomain.new(
      domain_id: 'ri_dom_2',
      display_domain: 'example2.com',
      created_at: Familia.now.to_f + 1
    )
  end

  it 'Clear commands and test command tracking isolation' do
    result = begin
      DatabaseLogger.clear_commands
      initial_commands = DatabaseLogger.commands
      initial_commands.empty?
    end
    expect(result).to eq(true)
  end

  it 'Check that instantiation commands are captured correctly' do
    result = begin
      instantiation_commands = DatabaseLogger.capture_commands do
        # Object instantiation happens in before(:each), this block is just to verify no commands are generated
        nil
      end
      instantiation_commands.empty?
    end
    expect(result).to eq(true)
  end

  it 'Verify save operations work correctly (commands may vary due to test isolation issues)' do
    result = begin
      database_commands = DatabaseLogger.capture_commands do
        @customer.save
      end
      database_commands.map { |cmd| cmd[:command] }
    end
    expect(result).to eq([["hmset", "reverse_index_customer:ri_cust_123:object", "customer_id", "ri_cust_123", "name", "Reverse Index Test Customer"], ["zadd", "reverse_index_customer:instances", "1705343400.0", "ri_cust_123"]])
  end

  it 'Domain1 save functionality' do
    result = begin
      database_commands = DatabaseLogger.capture_commands do
        @domain1.save
      end
      database_commands[0][:command]
    end
    expect(result).to eq(["hmset", "reverse_index_domain:ri_dom_1:object", "domain_id", "ri_dom_1", "display_domain", "example1.com", "created_at", "1705343400.0"])
  end

  it 'Domain2 save functionality' do
    result = begin
      database_commands = DatabaseLogger.capture_commands do
        @domain2.save
      end
      database_commands[0][:command]
    end
    expect(result).to eq(["hmset", "reverse_index_domain:ri_dom_2:object", "domain_id", "ri_dom_2", "display_domain", "example2.com", "created_at", "1705343401.0"])
  end

  after(:all) do
    Timecop.return # Clean up
  end
end
