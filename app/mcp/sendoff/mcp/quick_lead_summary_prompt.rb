require "mcp"
module Sendoff
  module Mcp
    class QuickLeadSummaryPrompt < ::MCP::Prompt
      prompt_name "quick_lead_summary"
      title "Quick Lead Summary"
      description "Returns a tight summary of a lead suitable for ad-hoc analysis — company, pipeline status, thread history, and intent signals."

      arguments [
        ::MCP::Prompt::Argument.new(
          name: "email",
          description: "Lead email address",
          required: true
        )
      ]

      class << self
        def template(args, server_context: nil)
          email = (args[:email] || args["email"]).to_s.strip

          begin
            lead = Sendoff::Lead.find_by!(email: email.downcase)
            company = lead.company
            entry = Sendoff::PipelineEntry.where(lead: lead).order(updated_at: :desc).first
            notes = Sendoff::Note.where(notable: lead)
                                   .or(Sendoff::Note.where(notable: company))
                                   .order(created_at: :desc).limit(3)

            ctx = Sendoff::Drafter::Context.new(lead, intent: :cold).build
            threads = ctx[:thread_history]
            last_contact = ctx[:days_since_last_contact]

            summary = <<~SUMMARY
              Lead: #{lead.display_name} <#{lead.email}>
              Company: #{company&.name} (#{company&.domain}) — Segment: #{company&.segment}
              Pipeline: #{entry&.stage || "no entry"} | Warm score: #{entry&.warm_score}
              Reports viewed: #{entry&.reports_viewed || 0} | Last view: #{entry&.last_report_view || "never"}
              Email threads: #{threads.size} | Days since contact: #{last_contact || "never"}
              #{threads.map { |t| "  • #{t[:subject]} (#{t[:last_date]}, #{t[:messages]} msgs, via #{t[:account_email]})" }.join("\n")}
              Notes:
              #{notes.map { |n| "  • #{n.title.presence || "Note"}: #{n.body_md.to_s.first(200)}" }.join("\n")}
              Voice rules: #{ctx[:voice_rules].present? ? ctx[:voice_rules] : "none"}
            SUMMARY

            prompt = "Here is a summary of lead #{email}:\n\n#{summary}\n\nWhat would you like to know or do with this lead?"
          rescue ActiveRecord::RecordNotFound
            prompt = "Lead #{email} was not found. Use search_leads to find them."
          end

          ::MCP::Prompt::Result.new(
            description: "Quick summary for lead #{email}",
            messages: [
              ::MCP::Prompt::Message.new(
                role: "user",
                content: ::MCP::Content::Text.new(prompt)
              )
            ]
          )
        end
      end
    end
  end
end
