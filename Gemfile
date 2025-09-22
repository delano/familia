# Gemfile

source 'https://rubygems.org'

gemspec

group :test do
  gem 'concurrent-ruby', '~> 1.3.5', require: false
  gem 'ruby-prof'
  gem 'stackprof'
  gem 'tryouts', '~> 3.6.0', require: false
end

group :development, :test do
  gem 'debug', require: false
  gem 'irb', '~> 1.15.2', require: false
  gem 'kramdown', require: false
  gem 'rubocop', require: false
  gem 'rubocop-performance', require: false
  gem 'rubocop-thread_safety', require: false
  gem 'solargraph', require: false
  gem 'yard', '~> 0.9', require: false
end

group :optional do
  gem 'rbnacl', '~> 7.1', '>= 7.1.1'
end
