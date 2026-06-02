module Sendoff
  module Mcp
    class ScheduleDraftTool < BaseTool
      tool_name "schedule_draft"
      description "Schedules a draft to be sent at a future time. when_str can be 'tomorrow_morning' or an ISO 8601 datetime."

      input_schema(
        properties: {
          draft_id: { type: "string", description: "Draft UUID" },
          when_str: { type: "string", description: "'tomorrow_morning' or ISO 8601 datetime (e.g. 2026-05-20T09:00:00-05:00)" }
        },
        required: %w[draft_id when_str]
      )

      MORNING_HOUR = 9

      class << self
        def perform(draft_id:, when_str:, **_)
          draft = Sendoff::Draft.find(draft_id)

          scheduled_at = parse_time(when_str.to_s.strip)
          return text_response({ ok: false, error: "Invalid when_str: #{when_str.inspect}. Use 'tomorrow_morning' or ISO 8601." }) unless scheduled_at
          return text_response({ ok: false, error: "Scheduled time must be in the future" }) if scheduled_at <= Time.current

          draft.update!(status: :scheduled, scheduled_at: scheduled_at)

          if defined?(Sendoff::Drafts::DeliverJob)
            Sendoff::Drafts::DeliverJob.set(wait_until: scheduled_at).perform_later(draft.id)
          end

          delete_gmail_draft(draft)

          audit_write!(action: "mcp_schedule_draft", subject: draft,
                       recipient: draft.to_addr, detail: "scheduled_at=#{scheduled_at.iso8601}")

          text_response({
            ok: true,
            draft_id: draft.id,
            scheduled_at: scheduled_at.iso8601,
            label: scheduled_at.in_time_zone.strftime("%-I:%M %p, %a %b %-d")
          })
        end

        private

        def parse_time(when_str)
          case when_str
          when "tomorrow_morning"
            (Time.zone.today + 1).in_time_zone.change(hour: MORNING_HOUR)
          else
            Time.zone.parse(when_str)
          end
        rescue ArgumentError, TypeError
          nil
        end

        def delete_gmail_draft(draft)
          return if draft.gmail_draft_id.blank?
          Sendoff.config.gmail_client_for(draft.email_account).delete_draft(draft.gmail_draft_id)
        rescue => e
          Rails.logger.warn("[Sendoff::Mcp] schedule_draft: failed to delete Gmail draft: #{e.message}")
        end
      end
    end
  end
end
