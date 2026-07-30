# try/bug_fixes/overview_permission_example_try.rb
#
# frozen_string_literal: true

# Pins the "Permission Management" example in docs/overview.md. That section
# previously documented a `permission_tracking` DSL and fifteen instance methods
# that existed nowhere in lib/; this file runs the replacement example verbatim
# so it cannot drift back into fiction.

require_relative '../support/helpers/test_helpers'

OverviewSE = Familia::Features::Relationships::ScoreEncoding

class ::OverviewCustomer < Familia::Horreum
  feature :relationships
  identifier_field :custid
  field :custid
end

class ::OverviewDocument < Familia::Horreum
  feature :relationships
  identifier_field :doc_id
  field :doc_id
  field :title

  participates_in ::OverviewCustomer, :documents, type: :sorted_set
  participates_in ::OverviewCustomer, :archive, type: :set
end

@customer = ::OverviewCustomer.new(custid: 'overview_cust_1')
@customer.save
@customer.documents.delete!
@doc = ::OverviewDocument.new(doc_id: 'overview_doc_1', title: 'Roadmap')
@doc.save

## grant by encoding permission flags into the score you add with
@customer.add_documents_instance(@doc, OverviewSE.encode_score(Familia.now, [:read, :write]))
@customer.documents_with_permission(:write)
#=> ["overview_doc_1"]

## bits the grant did not include are filtered out
@customer.documents_with_permission(:delete)
#=> []

## defaults to :read when no flag is given
@customer.documents_with_permission
#=> ["overview_doc_1"]

## the participation-aware add also records the reverse index, which a raw
## collection.add would skip
@doc.participations.member?(@customer.documents.dbkey)
#=> true

## _with_permission is generated only for sorted_set participations -- a :set
## has no scores to carry permission bits
[@customer.respond_to?(:documents_with_permission), @customer.respond_to?(:archive_with_permission)]
#=> [true, false]

@customer.documents.delete!
@doc.participations.delete!
@customer.destroy!
@doc.destroy!
