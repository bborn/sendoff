module Sendoff
  module Drafts
    # Delivers a held draft. Enqueued by Drafts::Sender (async path) with a 60s
    # hold so an accidental send can be cancelled in the window. Calls back into
    # the Sender in immediate mode to perform the actual Gmail send.
    class DeliverJob < Sendoff::ApplicationJob
      queue_as :default

      def perform(draft_id)
        draft = Draft.find_by(id: draft_id)
        return unless draft
        return unless draft.sending?

        Sendoff::Drafts::Sender.call(draft, immediate: true)
      rescue Sendoff::Drafts::RateLimitExceeded => e
        Rails.logger.error("Sendoff::Drafts::DeliverJob rate limit for draft_id=#{draft_id}: #{e.message}")
        draft&.update_columns(status: "pending", send_job_id: nil)
      rescue => e
        Rails.logger.error("Sendoff::Drafts::DeliverJob#perform draft_id=#{draft_id}: #{e.class}: #{e.message}\n#{e.backtrace&.first(5)&.join("\n")}")
        raise
      end
    end
  end
end
