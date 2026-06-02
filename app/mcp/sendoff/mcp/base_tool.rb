require "mcp"
module Sendoff
  module Mcp
    # Base class for all Sendoff Mcp tools. Wraps the gem's ::MCP::Tool with
    # uniform error handling, a JSON text response helper, lead lookup, and the
    # audit-log write every action tool must perform (actor = "mcp").
    class BaseTool < ::MCP::Tool
      class << self
        def call(server_context: nil, **args)
          perform(**args)
        rescue ActiveRecord::RecordNotFound => e
          text_response({ ok: false, error: "Not found: #{e.message}" })
        rescue => e
          Rails.logger.error("[Sendoff::Mcp] #{name} error: #{e.message}\n#{e.backtrace.first(3).join("\n")}")
          text_response({ ok: false, error: e.message })
        end

        def perform(**_args)
          raise NotImplementedError, "#{name} must implement perform"
        end

        def text_response(data)
          ::MCP::Tool::Response.new([ { type: "text", text: data.to_json } ])
        end

        def find_lead(id_or_email)
          val = id_or_email.to_s.strip
          if val.include?("@")
            Sendoff::Lead.find_by!(email: val.downcase)
          else
            Sendoff::Lead.find(val)
          end
        end

        # Every write tool logs an AuditLog row with actor "mcp".
        def audit_write!(action:, subject: nil, detail: nil, recipient: nil)
          Sendoff::AuditLog.create!(
            actor: "mcp",
            action: action,
            subject_type: subject&.class&.name,
            subject_id: subject&.id&.to_s,
            recipient: recipient,
            detail: detail,
            created_at: Time.current
          )
        end
      end
    end
  end
end
