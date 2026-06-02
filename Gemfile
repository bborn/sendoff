source "https://rubygems.org"

# Specify your gem's dependencies in sendoff.gemspec.
gemspec

gem "puma"
gem "pg"
gem "propshaft"

# Background jobs (the dummy app uses Solid Queue, like a real host app would).
gem "solid_queue", "~> 1.0"

# Omakase Ruby styling [https://github.com/rails/rubocop-rails-omakase/]
gem "rubocop-rails-omakase", require: false

group :development, :test do
  gem "debug", ">= 1.0.0"
  gem "rspec-rails", "~> 7.0"
  gem "factory_bot_rails"
  gem "faker"
end
