require "spec_helper"

ENV["RAILS_ENV"] ||= "test"
require_relative "dummy/config/environment"

abort("The Rails environment is running in production mode!") if Rails.env.production?

require "rspec/rails"
require "factory_bot_rails"

# Load support files (shared contexts, fake adapters, etc.)
Dir[File.join(__dir__, "support/**/*.rb")].sort.each { |f| require f }

begin
  ActiveRecord::Migration.maintain_test_schema!
rescue ActiveRecord::PendingMigrationError => e
  abort e.to_s.strip
end

RSpec.configure do |config|
  config.fixture_paths = [ File.expand_path("fixtures", __dir__) ]
  config.use_transactional_fixtures = true
  config.infer_spec_type_from_file_location!
  config.filter_rails_from_backtrace!

  config.include FactoryBot::Syntax::Methods

  # Every example starts from default engine configuration, then opts into the
  # network-free fakes. Individual specs can override.
  config.before(:each) do
    Sendoff.reset_configuration!
    Sendoff.config.llm_client = Sendoff::LLM::FakeClient.new
    Sendoff.config.gmail_client_factory = ->(account) { Sendoff::Gmail::FakeClient.new(account) }
  end
end
