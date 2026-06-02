require_relative "lib/sendoff/version"

Gem::Specification.new do |spec|
  spec.name        = "sendoff"
  spec.version     = Sendoff::VERSION
  spec.authors     = [ "Bruno Bornsztein" ]
  spec.email       = [ "bruno.bornsztein@gmail.com" ]
  spec.homepage    = "https://github.com/bborn/sendoff"
  spec.summary     = "Self-hosted AI that writes and sends your sales outreach, in your voice."
  spec.description = "Sendoff handles outbound sales for you: it drafts emails in your voice, " \
                     "checks them for hallucinations, holds to your sending rules, and sends via " \
                     "Gmail — driven by an LLM and steerable by an agent over MCP. It is not a CRM. " \
                     "Where your leads come from plugs in via a small adapter; everything else " \
                     "(drafting, critics, send-safety, the pipeline it runs internally) ships in the box."
  spec.license     = "MIT"

  spec.metadata["homepage_uri"]           = spec.homepage
  spec.metadata["source_code_uri"]        = spec.homepage
  spec.metadata["rubygems_mfa_required"]  = "true"

  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    Dir["{app,config,db,lib}/**/*", "MIT-LICENSE", "Rakefile", "README.md"]
  end

  spec.required_ruby_version = ">= 3.2"

  spec.add_dependency "rails", ">= 7.2"
  spec.add_dependency "google-apis-gmail_v1"
  spec.add_dependency "googleauth"
  spec.add_dependency "mcp"

  # Admin UI (Hotwire). The engine ships a mountable admin interface.
  spec.add_dependency "turbo-rails"
  spec.add_dependency "stimulus-rails"
  spec.add_dependency "importmap-rails"
end
