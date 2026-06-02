module Sendoff
  # MCP (Model Context Protocol) endpoint. Accepts JSON-RPC over POST /mcp.
  #
  # Auth: a single static key in ENV["SENDOFF_MCP_API_KEY"], compared against the
  # X-API-KEY request header. Fails closed — if the env var is blank, every
  # request is rejected (401). No key is ever hardcoded.
  class McpController < ApplicationController
    skip_forgery_protection
    before_action :authenticate_mcp_request!

    def handle
      Current.actor = "mcp"
      server = Sendoff::Mcp::Server.build
      result = server.handle_json(request.body.read)
      render body: result, content_type: "application/json"
    ensure
      Current.reset
    end

    private

    def authenticate_mcp_request!
      api_key = request.headers["X-API-KEY"].to_s.strip
      expected = ENV["SENDOFF_MCP_API_KEY"].to_s.strip

      if expected.blank? || api_key.blank? ||
         !ActiveSupport::SecurityUtils.secure_compare(api_key, expected)
        render json: { error: "Unauthorized" }, status: :unauthorized
      end
    end
  end
end
