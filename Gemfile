# frozen_string_literal: true

source 'https://rubygems.org'

gemspec

group :development, :test do
  # byebug only works with MRI
  gem 'byebug', '~> 11.0', require: false if RUBY_ENGINE == 'ruby'
  gem 'pry-byebug', '~> 3.10.1', require: false if RUBY_ENGINE == 'ruby'
  gem 'rubocop', require: false
  gem 'rubocop-performance', require: false
  gem 'rubocop-thread_safety', require: false
  gem 'tryouts', '~> 2.4', require: false
  gem 'yard', '~> 0.9', require: false
  gem 'kramdown', require: false  # Required for YARD markdown processing
end
