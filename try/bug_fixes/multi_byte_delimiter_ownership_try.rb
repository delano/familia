# try/bug_fixes/multi_byte_delimiter_ownership_try.rb
#
# frozen_string_literal: true

# RecordKeyOwnership compares keys as bytes. With a delimiter of more than
# one byte, a candidate split must still start at a whole delimiter, and
# the multi_index rebuild and audit must still give a key to the existing
# record with the longest identifier. This file sets Familia.delim to "→"
# (three bytes in UTF-8) and restores it in the teardown.

require_relative '../support/helpers/test_helpers'

class ::MbdCo < Familia::Horreum
  feature :relationships
  identifier_field :cid
  field :cid
  set :tags
end

class ::MbdEmp < Familia::Horreum
  feature :relationships
  identifier_field :eid
  field :eid
  field :dept
  multi_index :dept, :dept_index, within: ::MbdCo
  participates_in ::MbdCo, :staff
end

@ownership = Familia::Features::Relationships::Indexing::RecordKeyOwnership
@original_delim = Familia.delim
Familia.delim('→')
@client = Familia.dbclient
delete_test_dbkeys(MbdCo, MbdEmp)

@companies = ['c-1', 'c-1→dept_index→x'].each_with_index.map do |company_id, idx|
  company = MbdCo.new(cid: company_id)
  company.save
  employee = MbdEmp.new(eid: "e#{idx}", dept: 'ops')
  employee.save
  employee.add_to_mbd_co_staff(company)
  employee.add_to_mbd_co_dept_index(company)
  company
end

## Keys use the three-byte delimiter
[Familia.delim.bytesize, @companies.map { |company| company.dept_index_for('ops').dbkey }]
#=> [3, ["mbd_co→c-1→dept_index→ops", "mbd_co→c-1→dept_index→x→dept_index→ops"]]

## Candidate splits are byte offsets of whole delimiters
@names = { fields: ['tags'.b], indexes: ['dept_index'.b] }
@rest = 'c-1→dept_index→x→dept_index→ops'.b
@offsets = @ownership.candidate_split_offsets(@rest, '→'.b, @names, 'c-1'.bytesize)
[@offsets, @offsets.map { |offset| @rest.byteslice(0, offset).force_encoding('UTF-8') }]
#=> [[20], ["c-1→dept_index→x"]]

## A two-byte delimiter finds every split, including one that ends in part of a delimiter
@two = 'a:::dept_index'.b
@ownership.candidate_split_offsets(@two, '::'.b, @names, 0)
#=> [2]

## The bucket of the longer scope is owned by that scope
@ownership.other_record_key_owner(@companies.last.dept_index_for('ops').dbkey, @companies.first)
#=> "mbd_co→c-1→dept_index→x→object"

## Rebuilding the shorter scope keeps the longer scope's bucket
[@companies.first.rebuild_dept_index, @companies.map { |company| company.dept_index_for('ops').members }]
#=> [1, [["e0"], ["e1"]]]

## Rebuilding the longer scope keeps the shorter scope's bucket
[@companies.last.rebuild_dept_index, @companies.map { |company| company.dept_index_for('ops').members }]
#=> [1, [["e0"], ["e1"]]]

## The audit reads each bucket for its own scope
@audit = MbdEmp.audit_multi_indexes.first
[@audit[:status], @audit[:missing], @audit[:stale_members], @audit[:orphaned_keys], @audit[:foreign_owned_keys]]
#=> [:ok, [], [], [], []]

## The set field of the longer scope is not a bucket of the shorter one
@companies.last.tags.add('t')
@companies.first.rebuild_dept_index
[@companies.last.tags.members, MbdEmp.audit_multi_indexes.first[:status]]
#=> [["t"], :ok]

# Teardown
delete_test_dbkeys(MbdCo, MbdEmp)
Familia.delim(@original_delim)
