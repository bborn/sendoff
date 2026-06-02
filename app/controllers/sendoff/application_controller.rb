module Sendoff
  class ApplicationController < ActionController::Base
    protect_from_forgery with: :exception
    before_action :set_actor

    private

    # Sets Sendoff::Current.actor for the request so audit logs are attributed.
    # CurrentAttributes resets automatically between requests. Hosts mount this
    # behind their own auth (e.g. Cloudflare Access) and can override
    # `current_actor`; the default reads a common proxy header, else "admin".
    def set_actor
      Sendoff::Current.actor = current_actor
    end

    def current_actor
      request.headers["Cf-Access-Authenticated-User-Email"].presence || "admin"
    end
  end
end
