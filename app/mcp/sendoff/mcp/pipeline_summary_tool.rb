module Sendoff
  module Mcp
    class PipelineSummaryTool < BaseTool
      tool_name "pipeline_summary"
      description "Returns a kanban snapshot: count per stage plus the first 25 entry summaries per stage."

      input_schema(properties: {})

      class << self
        def perform(**_)
          stages = Sendoff::PipelineEntry.stages.keys
          snapshot = {}

          stages.each do |stage|
            entries = Sendoff::PipelineEntry.where(stage: stage)
                                              .includes(:lead, :company)
                                              .order(updated_at: :desc)
                                              .limit(25)
            count = Sendoff::PipelineEntry.where(stage: stage).count

            snapshot[stage] = {
              count: count,
              entries: entries.map { |e|
                {
                  id: e.id,
                  lead_email: e.lead&.email,
                  lead_name: e.lead&.display_name,
                  company: e.company&.name,
                  stage: e.stage,
                  updated_at: e.updated_at
                }
              }
            }
          end

          text_response({ ok: true, pipeline: snapshot })
        end
      end
    end
  end
end
