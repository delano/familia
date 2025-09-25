# Test cleanup helper for managing anonymous classes and test isolation
#
# This module provides utilities to create and cleanup test classes that
# inherit from Familia classes. Without proper cleanup, anonymous classes
# pollute the Familia.members registry causing test failures.

module TestCleanup
  @test_classes = []

  class << self
    attr_reader :test_classes

    # Create a test class that inherits from the given base class.
    # The created class is automatically tracked for cleanup.
    #
    # @param base_class [Class] The class to inherit from (e.g., Familia::Horreum)
    # @param block [Proc] Block to define the class body
    # @return [Class] The created test class
    def create_test_class(base_class, &block)
      test_class = Class.new(base_class, &block)
      track_test_class(test_class)
      test_class
    end

    # Track a test class for cleanup. Use this when you create test classes
    # directly with Class.new instead of using create_test_class.
    #
    # @param klass [Class] The test class to track
    # @return [Class] The tracked class
    def track_test_class(klass)
      @test_classes << klass unless @test_classes.include?(klass)
      klass
    end

    # Remove all tracked test classes from Familia.members and clear
    # the tracking array. This should be called in test teardown.
    #
    # @return [Array<Class>] The classes that were removed
    def cleanup_test_classes
      removed_classes = []

      @test_classes.each do |test_class|
        if Familia.members.include?(test_class)
          Familia.unload_member(test_class)
          removed_classes << test_class
        end
      end

      @test_classes.clear
      removed_classes
    end

    # Clean up all anonymous classes from Familia.members.
    # This is a more aggressive cleanup that removes any class with nil name.
    #
    # @return [Array<Class>] The anonymous classes that were removed
    def cleanup_anonymous_classes
      Familia.clear_anonymous_members
    end

    # Perform complete test cleanup - both tracked and anonymous classes
    #
    # @return [Hash] Summary of cleanup performed
    def complete_cleanup
      tracked_removed = cleanup_test_classes
      anonymous_removed = cleanup_anonymous_classes

      {
        tracked_classes_removed: tracked_removed.size,
        anonymous_classes_removed: anonymous_removed.size,
        total_removed: tracked_removed.size + anonymous_removed.size
      }
    end
  end
end

# Automatically perform cleanup if we're in test mode
# This ensures cleanup happens even if tests don't explicitly call it
at_exit do
  if Familia.test_mode? && TestCleanup.test_classes.any?
    cleanup_result = TestCleanup.complete_cleanup
    if cleanup_result[:total_removed] > 0
      puts "[TestCleanup] Cleaned up #{cleanup_result[:total_removed]} test classes on exit"
    end
  end
end
