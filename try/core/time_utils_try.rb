require_relative '../helpers/test_helpers'

module RefinedContext
  using Familia::Refinements::TimeLiterals

  def self.eval_in_refined_context(code)
    eval(code)
  end

  def self.instance_eval_in_refined_context(code)
    instance_eval(code)
  end
end

# Test TimeLiterals refinement

## Numeric#months - convert number to months in seconds
result = RefinedContext.eval_in_refined_context("1.month")
result.round(0)
#=> 2629746.0

## Numeric#months - plural form
result = RefinedContext.instance_eval_in_refined_context("2.months")
result.round(0)
#=> 5259492.0

## Numeric#years - convert number to years in seconds
result = RefinedContext.eval_in_refined_context("1.year")
result.round(0)
#=> 31556952.0

## Numeric#in_months - convert seconds to months
RefinedContext.instance_eval_in_refined_context("2629746.in_months")
#=> 1.0

## Numeric#in_years - convert seconds to years
result = RefinedContext.eval_in_refined_context("#{Familia::Refinements::TimeLiterals::PER_YEAR}.in_years")
result.round(1)
#=> 1.0

## String#in_seconds - parse month string
RefinedContext.instance_eval_in_refined_context("'1mo'.in_seconds")
#=> 2629746.0

## String#in_seconds - parse month string (long form)
RefinedContext.eval_in_refined_context("'2months'.in_seconds")
#=> 5259492.0

## String#in_seconds - parse year string
result = RefinedContext.instance_eval_in_refined_context("'1y'.in_seconds")
result.round(0)
#=> 31556952.0

## Numeric#age_in - calculate age in months from timestamp (approximately 1 month ago)
timestamp = Familia.now - Familia::Refinements::TimeLiterals::PER_MONTH
result = RefinedContext.eval_in_refined_context("#{timestamp}.age_in(:months)")
(result - 1.0).abs < 0.01
#=> true

## Numeric#age_in - calculate age in years from timestamp (approximately 1 year ago)
timestamp = Familia.now - Familia::Refinements::TimeLiterals::PER_YEAR
result = RefinedContext.instance_eval_in_refined_context("#{timestamp}.age_in(:years)")
(result - 1.0).abs < 0.01
#=> true

## Numeric#months_old - convenience method for age_in(:months)
timestamp = Familia.now - Familia::Refinements::TimeLiterals::PER_MONTH
result = RefinedContext.eval_in_refined_context("#{timestamp}.months_old")
(result - 1.0).abs < 0.01
#=> true

## Numeric#years_old - convenience method for age_in(:years)
timestamp = Familia.now - Familia::Refinements::TimeLiterals::PER_YEAR
result = RefinedContext.instance_eval_in_refined_context("#{timestamp}.years_old")
(result - 1.0).abs < 0.01
#=> true

## Numeric#months_old - should NOT return seconds (the original bug)
timestamp = Familia.now - Familia::Refinements::TimeLiterals::PER_MONTH
result = RefinedContext.eval_in_refined_context("#{timestamp}.months_old")
result.between?(0.9, 1.1)  # Should be ~1 month, not millions of seconds
#=> true

## Numeric#years_old - should NOT return seconds (the original bug)
timestamp = Familia.now - Familia::Refinements::TimeLiterals::PER_YEAR
result = RefinedContext.instance_eval_in_refined_context("#{timestamp}.years_old")
result.between?(0.9, 1.1)  # Should be ~1 year, not millions of seconds
#=> true

## age_in with from_time parameter - months
past_time = Familia.now - (2 * Familia::Refinements::TimeLiterals::PER_MONTH)  # 2 months ago
from_time = Familia.now - Familia::Refinements::TimeLiterals::PER_MONTH  # 1 month ago
result = RefinedContext.eval_in_refined_context("#{past_time.to_f}.age_in(:months, #{from_time.to_f})")
(result - 1.0).abs < 0.01
#=> true

## age_in with from_time parameter - years
past_time = Familia.now - (2 * Familia::Refinements::TimeLiterals::PER_YEAR)  # 2 years ago
from_time = Familia.now - Familia::Refinements::TimeLiterals::PER_YEAR  # 1 year ago
result = RefinedContext.instance_eval_in_refined_context("#{past_time.to_f}.age_in(:years, #{from_time.to_f})")
(result - 1.0).abs < 0.01
#=> true

## Verify month constant is approximately correct (30.437 days)
expected_seconds_per_month = 30.437 * 24 * 60 * 60
Familia::Refinements::TimeLiterals::PER_MONTH.round(0)
#=> 2629746.0

## Verify year constant (365.2425 days - Gregorian year)
expected_seconds_per_year = 365.2425 * 24 * 60 * 60
Familia::Refinements::TimeLiterals::PER_YEAR.round(0)
#=> 31556952.0

## UNIT_METHODS contains months mapping
Familia::Refinements::TimeLiterals::UNIT_METHODS['months']
#=> :months

## UNIT_METHODS contains mo mapping
Familia::Refinements::TimeLiterals::UNIT_METHODS['mo']
#=> :months

## UNIT_METHODS contains month mapping
Familia::Refinements::TimeLiterals::UNIT_METHODS['month']
#=> :months

## Calendar consistency - 12 months equals 1 year (fix for inconsistency issue)
result1 = RefinedContext.eval_in_refined_context("12.months")
result2 = RefinedContext.instance_eval_in_refined_context("1.year")
result1 == result2
#=> true
