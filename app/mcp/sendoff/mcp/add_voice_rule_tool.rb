module Sendoff
  module Mcp
    class AddVoiceRuleTool < BaseTool
      tool_name "add_voice_rule"
      description "Creates a new voice rule to guide future email drafting. Scope controls which draft types it applies to."

      input_schema(
        properties: {
          scope: { type: "string", description: "Scope: all, cold_prospect, customer_success, reengage_cold, reengage_customer" },
          rule: { type: "string", description: "The rule text (e.g. 'Always end with a specific call to action')" }
        },
        required: %w[scope rule]
      )

      class << self
        def perform(scope:, rule:, **_)
          unless Sendoff::VoiceRule::SCOPES.include?(scope.to_s)
            return text_response({ ok: false, error: "Invalid scope '#{scope}'. Valid: #{Sendoff::VoiceRule::SCOPES.join(", ")}" })
          end

          voice_rule = Sendoff::VoiceRule.create!(
            scope: scope,
            rule: rule.to_s.strip,
            created_by: "mcp"
          )

          audit_write!(action: "mcp_add_voice_rule", subject: voice_rule,
                       detail: "scope=#{scope} rule=#{rule.to_s.first(200)}")

          text_response({ ok: true, id: voice_rule.id, scope: voice_rule.scope, rule: voice_rule.rule })
        end
      end
    end
  end
end
