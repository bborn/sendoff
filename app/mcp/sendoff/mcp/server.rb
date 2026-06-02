require "mcp"
module Sendoff
  module Mcp
    # Builds the Sendoff Mcp server: registers all tools, prompts, and
    # resource templates, and wires the resources_read_handler that resolves
    # sdr:// URIs to JSON payloads.
    class Server
      TOOLS = [
        SearchLeadsTool,
        GetLeadContextTool,
        ListDraftsTool,
        GetDraftTool,
        GetVoiceRulesTool,
        PipelineSummaryTool,
        QueueDraftTool,
        RefineDraftTool,
        SendDraftTool,
        ScheduleDraftTool,
        DiscardDraftTool,
        MoveToStageTool,
        SkipLeadTool,
        AddVoiceRuleTool,
        AddNoteTool
      ].freeze

      PROMPTS = [
        ComposeDraftForPrompt,
        QuickLeadSummaryPrompt
      ].freeze

      def self.resource_templates
        [
          ::MCP::ResourceTemplate.new(
            uri_template: "sdr://lead/{id}",
            name: "lead",
            title: "Lead",
            description: "Lead with company, pipeline entry, email events, and notes",
            mime_type: "application/json"
          ),
          ::MCP::ResourceTemplate.new(
            uri_template: "sdr://draft/{id}",
            name: "draft",
            title: "Draft",
            description: "Draft email with prompt and raw LLM response",
            mime_type: "application/json"
          ),
          ::MCP::ResourceTemplate.new(
            uri_template: "sdr://voice-rules",
            name: "voice-rules",
            title: "Voice Rules",
            description: "All active voice rules",
            mime_type: "application/json"
          ),
          ::MCP::ResourceTemplate.new(
            uri_template: "sdr://pipeline",
            name: "pipeline",
            title: "Pipeline",
            description: "Kanban snapshot with counts per stage",
            mime_type: "application/json"
          )
        ]
      end

      def self.build
        server = ::MCP::Server.new(
          name: "sdr-engine",
          version: Sendoff::VERSION,
          tools: TOOLS,
          prompts: PROMPTS,
          resource_templates: resource_templates
        )

        server.resources_read_handler do |request|
          uri = request[:uri].to_s
          content = read_resource(uri)
          [ { type: "text", text: content.to_json, uri: uri, mimeType: "application/json" } ]
        end

        server
      end

      def self.read_resource(uri)
        case uri
        when %r{\Asdr://lead/(.+)\z}
          lead_resource($1)
        when %r{\Asdr://draft/(.+)\z}
          draft_resource($1)
        when "sdr://voice-rules"
          voice_rules_resource
        when "sdr://pipeline"
          pipeline_resource
        else
          { error: "Unknown resource URI: #{uri}" }
        end
      rescue ActiveRecord::RecordNotFound => e
        { error: "Not found: #{e.message}" }
      rescue => e
        Rails.logger.error("[Sendoff::Mcp] read_resource #{uri}: #{e.message}")
        { error: e.message }
      end

      def self.lead_resource(id)
        lead = id.include?("@") ? Sendoff::Lead.find_by!(email: id.downcase) : Sendoff::Lead.find(id)
        company = lead.company
        entry = Sendoff::PipelineEntry.where(lead: lead).order(updated_at: :desc).first
        email_events = Sendoff::EmailEvent.where(lead: lead).order(sent_at: :desc).limit(5).map { |e|
          { direction: e.direction, subject: e.subject, sent_at: e.sent_at, from: e.from_addr }
        }
        notes = Sendoff::Note.where(notable: lead).order(created_at: :desc).limit(5).map { |n|
          { title: n.title, body: n.body_md, created_at: n.created_at }
        }

        {
          lead: {
            id: lead.id, email: lead.email, name: lead.display_name,
            first_name: lead.first_name, last_name: lead.last_name, role: lead.role
          },
          company: company && {
            id: company.id, name: company.name, domain: company.domain, segment: company.segment
          },
          pipeline_entry: entry && {
            id: entry.id, stage: entry.stage, warm_score: entry.warm_score,
            reports_viewed: entry.reports_viewed, last_report_view: entry.last_report_view
          },
          email_events: email_events,
          notes: notes
        }
      end

      def self.draft_resource(id)
        draft = Sendoff::Draft.includes(:lead, :email_account).find(id)
        {
          id: draft.id,
          to_addr: draft.to_addr,
          subject: draft.subject,
          body_html: draft.body_html,
          status: draft.status,
          intent: draft.intent,
          gmail_draft_id: draft.gmail_draft_id,
          prompt_used: draft.prompt_used,
          raw_response: draft.raw_response,
          created_at: draft.created_at,
          lead: { id: draft.lead&.id, email: draft.lead&.email, name: draft.lead&.display_name },
          company: { name: draft.lead&.company&.name, domain: draft.lead&.company&.domain }
        }
      end

      def self.voice_rules_resource
        rules = Sendoff::VoiceRule.where(active: true).order(:scope, :created_at).map { |r|
          { id: r.id, scope: r.scope, rule: r.rule, created_at: r.created_at }
        }
        { voice_rules: rules, count: rules.size }
      end

      def self.pipeline_resource
        stages = Sendoff::PipelineEntry.stages.keys
        { pipeline: stages.index_with { |s| Sendoff::PipelineEntry.where(stage: s).count } }
      end
    end
  end
end
