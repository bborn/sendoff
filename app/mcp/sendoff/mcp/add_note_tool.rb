module Sendoff
  module Mcp
    class AddNoteTool < BaseTool
      tool_name "add_note"
      description "Creates a note attached to a lead or company. Provide at least one of lead_id or company_id."

      input_schema(
        properties: {
          content: { type: "string", description: "Note body (markdown)" },
          title: { type: "string", description: "Optional note title" },
          lead_id: { type: "string", description: "Lead UUID or email address to attach the note to" },
          company_id: { type: "string", description: "Company UUID to attach the note to" }
        },
        required: [ "content" ]
      )

      class << self
        def perform(content:, title: nil, lead_id: nil, company_id: nil, **_)
          content = content.to_s.strip
          return text_response({ ok: false, error: "Content cannot be blank" }) if content.blank?
          return text_response({ ok: false, error: "Provide at least one of lead_id or company_id" }) if lead_id.blank? && company_id.blank?

          notable = if lead_id.present?
            find_lead(lead_id)
          else
            Sendoff::Company.find(company_id)
          end

          note = Sendoff::Note.create!(
            notable: notable,
            title: title.to_s.presence,
            body_md: content,
            author: "mcp",
            source: "mcp"
          )

          audit_write!(action: "mcp_add_note", subject: note,
                       detail: "notable=#{notable.class.name}##{notable.id} title=#{title.to_s.first(100)}")

          text_response({ ok: true, id: note.id, notable_type: notable.class.name, notable_id: notable.id })
        end
      end
    end
  end
end
