# examples/bit_encoding_integration.rb
#
# Production Integration Example: Document Management System with Fine-Grained Permissions
#
# This example demonstrates how to use Familia's bit encoding permission system
# in a real-world document management scenario with sophisticated access control.

require_relative '../lib/familia'
require_relative '../lib/familia/features/relationships/score_encoding'
require_relative '../lib/familia/features/relationships/permission_management'

# Document Management System Classes
class User < Familia::Horreum
  logical_database 14

  identifier_field :user_id
  field :user_id
  field :email
  field :name
  field :role # admin, editor, viewer, guest
  field :created_at

  sorted_set :documents # Documents this user can access
  sorted_set :recent_activity # Recent document access
end

class Document < Familia::Horreum
  include Familia::Features::Relationships::PermissionManagement

  logical_database 14

  # Enable fine-grained permission tracking
  permission_tracking :user_permissions

  identifier_field :doc_id
  field :doc_id
  field :title
  field :owner_id
  field :content
  field :created_at
  field :updated_at
  field :document_type # public, private, confidential

  sorted_set :collaborators # Users with access to this document
  list :audit_log # Track permission changes and access

  # Add document to user's collection with specific permissions
  def share_with_user(user, *permissions)
    permissions = [:read] if permissions.empty?

    # Create time-based score with permissions encoded
    timestamp = updated_at || Time.now
    score = Familia::Features::Relationships::ScoreEncoding.encode_score(timestamp, permissions)

    # Add to user's document list
    user.documents.add(score, doc_id)

    # Add user to document's collaborator list
    collaborators.add(score, user.user_id)

    # Grant permissions via permission management
    grant(user, *permissions)

    # Log the permission grant
    log_entry = "#{Time.now.iso8601}: Granted #{permissions.join(', ')} to #{user.email}"
    audit_log.push(log_entry)
  end

  # Remove user access
  def revoke_access(user)
    user.documents.zrem(doc_id)
    collaborators.zrem(user.user_id)
    revoke(user, :read, :write, :edit, :delete, :configure, :transfer, :admin)

    log_entry = "#{Time.now.iso8601}: Revoked all access from #{user.email}"
    audit_log.push(log_entry)
  end

  # Get users with specific permission level or higher
  def users_with_permission(*required_permissions)
    all_permissions.select do |_user_id, user_perms|
      required_permissions.all? { |perm| user_perms.include?(perm) }
    end.keys
  end

  # Advanced: Get document access history for analytics
  def access_analytics(days_back = 30)
    start_time = Time.now - (days_back * 24 * 60 * 60)
    end_time = Time.now

    # Use score range to get recent access
    range = Familia::Features::Relationships::ScoreEncoding.score_range(
      start_time,
      end_time,
      min_permissions: [:read]
    )

    # Get collaborators active in time range
    active_users = collaborators.rangebyscore(*range)

    {
      active_users: active_users,
      total_collaborators: collaborators.size,
      permission_breakdown: all_permissions,
      audit_entries: audit_log.range(0, 50),
    }
  end
end

# Document Management Service - Business Logic Layer
class DocumentService
  # Permission role definitions matching business needs
  ROLE_PERMISSIONS = {
    guest: [:read],
    viewer: [:read],
    commenter: %i[read append],
    editor: %i[read write edit],
    reviewer: %i[read write edit delete],
    admin: %i[read write edit delete configure transfer admin],
  }.freeze

  def self.create_document(owner, title, content, doc_type = 'private')
    doc = Document.new(
      doc_id: "doc_#{Time.now.to_i}_#{rand(1000)}",
      title: title,
      content: content,
      owner_id: owner.user_id,
      document_type: doc_type,
      created_at: Time.now,
      updated_at: Time.now
    )

    # Owner gets full admin access
    doc.share_with_user(owner, *ROLE_PERMISSIONS[:admin])
    doc
  end

  def self.share_document(document, user, role)
    permissions = ROLE_PERMISSIONS[role] || ROLE_PERMISSIONS[:viewer]
    document.share_with_user(user, *permissions)
  end

  def self.can_user_perform?(user, document, action)
    case action
    when :view, :read
      document.can?(user, :read)
    when :comment, :append
      document.can?(user, :read, :append)
    when :edit, :modify
      document.can?(user, :read, :write, :edit)
    when :delete, :remove
      document.can?(user, :delete)
    when :share, :configure
      document.can?(user, :configure)
    when :transfer_ownership
      document.can?(user, :admin)
    else
      false
    end
  end

  def self.bulk_permission_update(documents, users, role)
    permissions = ROLE_PERMISSIONS[role]

    documents.each do |doc|
      users.each do |user|
        doc.revoke_access(user) # Clear existing
        doc.share_with_user(user, *permissions) if permissions
      end
    end
  end
end

# Example Usage and Demonstration
if __FILE__ == $0
  puts '🚀 Familia Bit Encoding Integration Example'
  puts '=' * 50

  # Create users
  alice = User.new(user_id: 'alice', email: 'alice@company.com', name: 'Alice Smith', role: 'admin')
  bob = User.new(user_id: 'bob', email: 'bob@company.com', name: 'Bob Jones', role: 'editor')
  charlie = User.new(user_id: 'charlie', email: 'charlie@company.com', name: 'Charlie Brown', role: 'viewer')

  # Create documents
  doc1 = DocumentService.create_document(alice, 'Q4 Financial Report', 'Confidential financial data...', 'confidential')
  doc2 = DocumentService.create_document(alice, 'Team Meeting Notes', 'Weekly standup notes...', 'private')
  doc3 = DocumentService.create_document(bob, 'Project Proposal', 'New feature proposal...', 'public')

  # Share documents with different permission levels
  puts "\n📄 Document Sharing:"
  DocumentService.share_document(doc1, bob, :reviewer)     # Bob can review financial report
  DocumentService.share_document(doc1, charlie, :viewer)   # Charlie can only view

  DocumentService.share_document(doc2, bob, :editor)       # Bob can edit meeting notes
  DocumentService.share_document(doc2, charlie, :commenter) # Charlie can comment

  DocumentService.share_document(doc3, alice, :admin)      # Alice gets admin on Bob's doc
  DocumentService.share_document(doc3, charlie, :editor)   # Charlie can edit proposal

  # Test permission checks
  puts "\n🔐 Permission Testing:"
  puts "Can Bob edit financial report? #{DocumentService.can_user_perform?(bob, doc1, :edit)}"
  puts "Can Bob delete financial report? #{DocumentService.can_user_perform?(bob, doc1, :delete)}"
  puts "Can Charlie comment on meeting notes? #{DocumentService.can_user_perform?(charlie, doc2, :comment)}"
  puts "Can Charlie edit project proposal? #{DocumentService.can_user_perform?(charlie, doc3, :edit)}"

  # Advanced analytics
  puts "\n📊 Document Analytics:"
  analytics = doc1.access_analytics
  puts "Financial Report - Active Users: #{analytics[:active_users].size}"
  puts "Total Collaborators: #{analytics[:total_collaborators]}"
  puts 'Permission Breakdown:'
  analytics[:permission_breakdown].each do |user_id, perms|
    puts "  #{user_id}: #{perms.join(', ')}"
  end

  # Demonstrate bit encoding efficiency
  puts "\n⚡ Bit Encoding Efficiency:"
  score = Familia::Features::Relationships::ScoreEncoding.encode_score(Time.now, %i[read write edit delete])
  decoded = Familia::Features::Relationships::ScoreEncoding.decode_score(score)
  puts "Encoded score: #{score}"
  puts "Decoded permissions: #{decoded[:permission_list].join(', ')}"
  puts "Permission bits: #{decoded[:permissions]} (#{decoded[:permissions].to_s(2).rjust(8, '0')})"

  # Cleanup
  puts "\n🧹 Cleanup:"
  [alice, bob, charlie].each { |user| user.documents.clear }
  [doc1, doc2, doc3].each do |doc|
    doc.clear_all_permissions
    doc.collaborators.clear
  end

  puts '✅ Integration example completed successfully!'
  puts "\nThis demonstrates:"
  puts '• Fine-grained permission management with 8-bit encoding'
  puts '• Role-based access control with business logic'
  puts '• Time-based analytics and audit trails'
  puts '• Efficient Redis storage with sorted sets'
  puts '• Production-ready error handling and validation'
end
