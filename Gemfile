# frozen_string_literal: true

source 'https://rubygems.org'

gemspec

group :test do
  if ENV['LOCAL_DEV']

    gem 'tryouts', path: '../../d/tryouts'

  else
    gem 'tryouts', '~> 3.0', require: false
  end
end


group :development, :test do
  # byebug only works with MRI
  gem 'byebug', '~> 11.0', require: false if RUBY_ENGINE == 'ruby'
  gem 'pry-byebug', '~> 3.10.1', require: false if RUBY_ENGINE == 'ruby'
  gem 'rubocop', require: false
  gem 'rubocop-performance', require: false
  gem 'rubocop-thread_safety', require: false
  gem 'kramdown', require: false  # Required for YARD markdown processing
  gem 'yard', '~> 0.9', require: false
end
