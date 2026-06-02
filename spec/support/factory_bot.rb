require "factory_bot"

# The dummy app is the Rails root, so factory_bot_rails only auto-discovers
# factories under spec/dummy. Point it at the engine's own spec/factories and
# reload so our namespaced factories register.
engine_factories = File.expand_path("../factories", __dir__)
unless FactoryBot.definition_file_paths.map(&:to_s).include?(engine_factories)
  FactoryBot.definition_file_paths << engine_factories
  FactoryBot.reload
end
