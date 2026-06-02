require "mcp"
module Sendoff
  module Mcp
    class ComposeDraftForPrompt < ::MCP::Prompt
      prompt_name "compose_draft_for"
      title "Compose Draft"
      description "Returns the full lead context as a prompt for the model to draft a cold outbound email, or triggers queue_draft if you want the Drafter to handle it."

      arguments [
        ::MCP::Prompt::Argument.new(
          name: "email",
          description: "Lead email address",
          required: true
        ),
        ::MCP::Prompt::Argument.new(
          name: "use_drafter",
          description: "If 'true', triggers the Drafter via queue_draft instead of asking the model to write the email",
          required: false
        )
      ]

      class << self
        def template(args, server_context: nil)
          email = (args[:email] || args["email"]).to_s.strip
          use_drafter = (args[:use_drafter] || args["use_drafter"]).to_s.downcase == "true"

          if use_drafter
            prompt = "Call the queue_draft tool with lead_id='#{email}' to trigger the Drafter. " \
                     "Then retrieve and show the resulting draft."
          else
            begin
              lead = Sendoff::Lead.find_by!(email: email.downcase)
              ctx = Sendoff::Drafter::Context.new(lead, intent: :cold).build
              prompt = build_compose_prompt(ctx)
            rescue ActiveRecord::RecordNotFound
              prompt = "Lead with email #{email} was not found in the database."
            end
          end

          ::MCP::Prompt::Result.new(
            description: "Compose a cold outbound email for #{email}",
            messages: [
              ::MCP::Prompt::Message.new(
                role: "user",
                content: ::MCP::Content::Text.new(prompt)
              )
            ]
          )
        end

        private

        def build_compose_prompt(ctx)
          persona = Sendoff.config.persona
          <<~PROMPT
            Draft a personalized cold outbound email for this lead on behalf of
            #{persona.sender_name} (#{persona.product_name}). Use the context below.

            LEAD: #{ctx[:lead].to_json}
            COMPANY: #{ctx[:company].to_json}
            ACCOUNT: #{ctx[:account].to_json}
            THREAD HISTORY: #{ctx[:thread_history].to_json}
            DOMAIN HISTORY: #{ctx[:domain_thread_history].to_json}
            DAYS SINCE LAST CONTACT: #{ctx[:days_since_last_contact]}
            VOICE RULES:
            #{ctx[:voice_rules]}

            Requirements:
            - Write in plain conversational prose, no bullet points
            - Personalize to the company's specific situation
            - Keep it under 150 words
            - Return JSON: {"subject": "...", "body_html": "..."}
          PROMPT
        end
      end
    end
  end
end
