# Gemfile

source 'https://rubygems.org'

gemspec

group :test do
  gem 'concurrent-ruby', '~> 1.3.6', require: false
  gem 'ruby-prof'
  gem 'stackprof'
  gem 'timecop', require: false
  gem 'tryouts', '~> 3.7.1', require: false
end

group :development, :test do
  gem 'benchmark', '~> 0.4', require: false
  gem 'debug', require: false
  # reek pulls in dry-configurable transitively (via dry-schema). Its 1.4.0
  # release bumped the minimum Ruby to 3.3, which breaks `bundle install` on
  # Ruby 3.2 (our gemspec's required_ruby_version floor). 1.4.0 only adds
  # Config#to_data, which we don't use (we don't use Dry::Configurable at all),
  # so cap below 1.4 to keep the dev bundle installable on Ruby 3.2.
  gem 'dry-configurable', '>= 1.3', '< 1.5', require: false
  gem 'irb', '~> 1.15.2', require: false
  gem 'json_schemer', '~> 2.0', require: false
  gem 'rake', '~> 13.0', require: false
  gem 'redcarpet', require: false
  gem 'reek', require: false
  gem 'rubocop', '~> 1.85.1', require: false
  gem 'rubocop-performance', require: false
  gem 'rubocop-thread_safety', require: false
  gem 'ruby-lsp', require: false
  gem 'yard', '~> 0.9', require: false
end

group :optional do
  gem 'rbnacl', '~> 7.1', '>= 7.1.1'
end
