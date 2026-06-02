module Sendoff
  module Mcp
    class MoveToStageTool < BaseTool
      tool_name "move_to_stage"
      description "Moves a pipeline entry to a different stage. Valid stages: new, drafting, review, contacted, replied, dud."

      input_schema(
        properties: {
          entry_id: { type: "string", description: "PipelineEntry UUID" },
          stage: { type: "string", description: "Target stage: new, drafting, review, contacted, replied, dud" }
        },
        required: %w[entry_id stage]
      )

      class << self
        def valid_stages
          Sendoff::PipelineEntry.stages.keys
        end

        def perform(entry_id:, stage:, **_)
          entry = Sendoff::PipelineEntry.includes(:lead, :company).find(entry_id)
          stage = stage.to_s.strip

          unless valid_stages.include?(stage)
            return text_response({ ok: false, error: "Invalid stage '#{stage}'. Valid: #{valid_stages.join(", ")}" })
          end

          old_stage = entry.stage
          entry.update!(stage: stage)

          audit_write!(action: "mcp_move_to_stage", subject: entry,
                       detail: "from=#{old_stage} to=#{stage} lead=#{entry.lead&.email}")

          text_response({
            ok: true,
            entry_id: entry.id,
            lead_email: entry.lead&.email,
            from_stage: old_stage,
            to_stage: entry.stage
          })
        end
      end
    end
  end
end
