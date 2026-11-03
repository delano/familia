# try/bug_fixes/refresh_operation_mode_try.rb
#
# frozen_string_literal: true

# Horreum#refresh! and HashKey#refresh! decide whether the key exists from
# the HGETALL reply. Inside a transaction, pipeline or atomic_write block
# that reply is a Redis::Future, and both methods raised NoMethodError
# (`empty?` and `transform_values` are not defined on Redis::Future). They
# now raise Familia::OperationModeError before sending anything, the way
# HashKey#claim_field and Lock#acquire refuse to run there.

require_relative '../support/helpers/test_helpers'

# Models for this file.
module RefreshOperationModeTry
  # A record with one hash collection.
  class Record < Familia::Horreum
    prefix :refresh_mode_record
    identifier_field :rid
    field :rid
    field :name
    hashkey :props
  end
end

@rec = RefreshOperationModeTry::Record.new(rid: 'refresh_mode_rec', name: 'stored')
@rec.save
@rec.props['color'] = 'blue'

## Horreum#refresh! inside a transaction raises OperationModeError
@rec.transaction { @rec.refresh! }
#=!> Familia::OperationModeError

## Horreum#refresh inside a pipeline raises OperationModeError
@rec.pipelined { @rec.refresh }
#=!> Familia::OperationModeError

## Horreum#refresh! inside atomic_write raises OperationModeError
@rec.name = 'pending'
@rec.atomic_write { @rec.refresh! }
#=!> Familia::OperationModeError

## the refused refresh! left the in-memory value alone
@rec.name
#=> 'pending'

## HashKey#refresh! inside a transaction raises OperationModeError
@rec.refresh!
@rec.transaction { @rec.props.refresh! }
#=!> Familia::OperationModeError

## HashKey#refresh inside a pipeline raises OperationModeError
@rec.pipelined { @rec.props.refresh }
#=!> Familia::OperationModeError

## both still work outside the block
[@rec.refresh.name, @rec.props.refresh!]
#=> ['stored', {'color' => 'blue'}]

delete_test_dbkeys(RefreshOperationModeTry::Record)
