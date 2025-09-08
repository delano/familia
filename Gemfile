# Gemfile

source 'https://rubygems.org'

gemspec

group :test do
  gem 'tryouts', '~> 3.6.0', require: false
  gem 'concurrent-ruby', '~> 1.3.5', require: false
  gem 'ruby-prof'
  gem 'stackprof'
end

group :development, :test do
  # byebug only works with MRI
  gem 'byebug', '~> 11.0', require: false if RUBY_ENGINE == 'ruby'
  gem 'irb', '~> 1.15.2', require: false
  gem 'kramdown', require: false # Required for YARD markdown processing
  gem 'pry-byebug', '~> 3.10.1', require: false if RUBY_ENGINE == 'ruby'
  gem 'rubocop', require: false
  gem 'rubocop-performance', require: false
  gem 'rubocop-thread_safety', require: false
  gem 'yard', '~> 0.9', require: false
end

group :optional do
  gem 'rbnacl', '~> 7.1', '>= 7.1.1'
end
