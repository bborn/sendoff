module Sendoff
  module Mcp
    class SearchLeadsTool < BaseTool
      tool_name "search_leads"
      description "Search leads by email, name, or domain. Returns id, email, name, company_name, and current pipeline stage."

      input_schema(
        properties: {
          q: { type: "string", description: "Search query (email, name, or company domain)" },
          limit: { type: "integer", description: "Max results (default 25, max 100)" }
        },
        required: [ "q" ]
      )

      class << self
        def perform(q:, limit: 25, **_)
          limit = [ limit.to_i, 100 ].min
          limit = 25 if limit < 1
          term = q.to_s.strip.downcase

          leads = Sendoff::Lead
            .joins(:company)
            .left_joins(:pipeline_entries)
            .select("sendoff_leads.*, sendoff_companies.name AS company_name, sendoff_pipeline_entries.stage AS current_stage")
            .where(
              "LOWER(sendoff_leads.email) LIKE :t OR LOWER(sendoff_leads.first_name) LIKE :t OR LOWER(sendoff_leads.last_name) LIKE :t OR LOWER(sendoff_leads.full_name) LIKE :t OR LOWER(sendoff_companies.domain) LIKE :t OR LOWER(sendoff_companies.name) LIKE :t",
              t: "%#{term}%"
            )
            .order("sendoff_leads.created_at DESC")
            .limit(limit)
            .distinct

          results = leads.map do |l|
            {
              id: l.id,
              email: l.email,
              name: l.display_name,
              company_name: l.company_name,
              stage: l.current_stage
            }
          end

          text_response({ ok: true, count: results.size, leads: results })
        end
      end
    end
  end
end
