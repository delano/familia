require_relative '../helpers/test_helpers'

module RefinedContext
  using Familia::Refinements::TimeLiterals

  # This helper evaluates code within the refined context using eval.
  # This works because eval executes the code as if it were written
  # at this location, making the refinements available.
  def self.eval_in_refined_context(code)
    eval(code)
  end

  # This helper also evaluates code in the refined context using instance_eval.
  # This provides an alternative approach for testing refinements.
  def self.instance_eval_in_refined_context(code)
    instance_eval(code)
  end
end

# Test core extensions

## String time parsing - seconds
RefinedContext.eval_in_refined_context("'60s'.in_seconds")
#=> 60.0

## String time parsing - minutes
RefinedContext.instance_eval_in_refined_context("'5m'.in_seconds")
#=> 300.0

## String time parsing - hours
RefinedContext.eval_in_refined_context("'2h'.in_seconds")
#=> 7200.0

## String time parsing - days
RefinedContext.instance_eval_in_refined_context("'1d'.in_seconds")
#=> 86_400.0

## String time parsing - years
RefinedContext.eval_in_refined_context("'1y'.in_seconds")
#=> 31556952.0

## Time::Units - second
RefinedContext.instance_eval_in_refined_context("1.second")
#=> 1

## Time::Units - minute
RefinedContext.eval_in_refined_context("1.minute")
#=> 60

## Time::Units - hour
RefinedContext.instance_eval_in_refined_context("1.hour")
#=> 3600

## Time::Units - day
RefinedContext.eval_in_refined_context("1.day")
#=> 86_400

## Time::Units - week
RefinedContext.instance_eval_in_refined_context("1.week")
#=> 604_800

## Numeric extension to_ms
RefinedContext.eval_in_refined_context("1000.to_ms")
#=> 1000000.0

## Numeric extension to_bytes - single byte
RefinedContext.instance_eval_in_refined_context("1.to_bytes")
#=> '1.00 B'

## Numeric extension to_bytes - kilobytes
RefinedContext.eval_in_refined_context("1024.to_bytes")
#=> '1.00 KiB'

## Numeric extension to_bytes - megabytes
RefinedContext.instance_eval_in_refined_context("(1024 * 1024).to_bytes")
#=> '1.00 MiB'
