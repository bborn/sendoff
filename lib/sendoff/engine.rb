require "turbo-rails"
require "stimulus-rails"
require "importmap-rails"

module Sendoff
  class Engine < ::Rails::Engine
    isolate_namespace Sendoff

    # Mount the engine's own importmap onto the host application's importmap so
    # the admin UI's JS (Stimulus controllers + SortableJS) resolves under the
    # `sendoff/` namespace, regardless of what the host app pins.
    initializer "sendoff.importmap", before: "importmap" do |app|
      if app.config.respond_to?(:importmap)
        app.config.importmap.paths << root.join("config/importmap.rb")
        app.config.importmap.cache_sweepers << root.join("app/javascript")
      end
    end

    # Serve the engine's bundled JS (app/javascript) and let the host resolve it.
    initializer "sendoff.assets" do |app|
      if app.config.respond_to?(:assets)
        app.config.assets.paths << root.join("app/javascript")
      end
    end
  end
end
