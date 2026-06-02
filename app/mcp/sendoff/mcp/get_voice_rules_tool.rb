module Sendoff
  module Mcp
    class GetVoiceRulesTool < BaseTool
      tool_name "get_voice_rules"
      description "Returns all active voice rules used to guide email drafting style."

      input_schema(properties: {})

      class << self
        def perform(**_)
          rules = Sendoff::VoiceRule.where(active: true).order(:scope, :created_at).map do |r|
            { id: r.id, scope: r.scope, rule: r.rule, created_at: r.created_at }
          end

          text_response({ ok: true, count: rules.size, voice_rules: rules })
        end
      end
    end
  end
end
