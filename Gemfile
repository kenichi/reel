source 'https://rubygems.org'

ruby RUBY_VERSION

gem 'jruby-openssl', platforms: :jruby

# Specify your gem's dependencies in reel.gemspec
gemspec

group :development do
  gem 'guard-rspec'
end

group :development, :test do
  gem 'h2', '0.4.0'
  gem 'pry'
  gem 'pry-byebug', platforms: :mri
end

group :test do
  gem 'rspec'
  gem 'coveralls', require: false
end
