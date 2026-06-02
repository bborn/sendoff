module Sendoff
  module InboundEmail
    # Records an inbound or BCC'd-outbound email as a Sendoff::EmailEvent.
    #
    # Input is a normalized Hash (see InboundEmailsController for how raw MIME
    # and pre-parsed provider payloads are reduced to this shape). All keys are
    # optional; the service is defensive and never raises on missing fields.
    #
    #   {
    #     message_id: "<abc@host>",     # RFC Message-ID (idempotency key)
    #     from:       "a@example.com",
    #     to:         ["b@example.com"],
    #     cc:         [...],
    #     bcc:        [...],
    #     subject:    "Re: hello",
    #     text:       "plain body",
    #     html:       "<p>html body</p>",
    #     in_reply_to:"<parent@host>",
    #     references: "<x@host> <y@host>",
    #     date:       Time or parseable String
    #   }
    #
    # Direction:
    #   from matches one of our Sendoff::EmailAccount  -> outbound (BCC'd copy)
    #   otherwise                                      -> inbound  (a reply)
    #
    # Matching: the counterpart lead is found by the *other* party's address —
    # the recipient for outbound, the sender for inbound. Company is taken from
    # the matched lead. If no lead matches, the event is still recorded with
    # lead/company nil so the record is never lost.
    #
    # Idempotency: dedupes on the RFC Message-ID stored in gmail_message_id
    # (the model's unique id column). Re-ingesting the same message returns the
    # existing event without creating a duplicate.
    class Ingest
      def self.call(parsed)
        new(parsed).call
      end

      def initialize(parsed)
        @parsed = (parsed || {}).symbolize_keys
      end

      def call
        if message_id.present?
          existing = EmailEvent.find_by(gmail_message_id: message_id)
          return existing if existing
        end

        sender_account = EmailAccount.find_by("LOWER(email) = ?", from_addr.to_s.downcase) if from_addr.present?
        direction = sender_account ? "outbound" : "inbound"

        counterpart = direction == "outbound" ? to_addrs.first : from_addr
        lead = counterpart.present? ? Lead.find_by("LOWER(email) = ?", counterpart.downcase) : nil

        event = EmailEvent.create!(
          direction: direction,
          email_account: sender_account,
          lead: lead,
          company: lead&.company,
          gmail_message_id: message_id.presence,
          gmail_thread_id: thread_id,
          from_addr: from_addr.to_s,
          to_addrs: to_addrs,
          cc_addrs: cc_addrs,
          bcc_addrs: bcc_addrs,
          subject: subject,
          body_text: body_text,
          body_html: html.presence,
          sent_at: sent_at
        )

        record_audit(event, lead)
        log_unmatched(event) if lead.nil?
        event
      rescue ActiveRecord::RecordNotUnique
        # Lost an idempotency race; the winner's row is authoritative.
        EmailEvent.find_by(gmail_message_id: message_id)
      end

      private

      attr_reader :parsed

      def message_id
        @message_id ||= parsed[:message_id].to_s.strip
      end

      def from_addr
        @from_addr ||= Array(parsed[:from]).first.to_s.strip
      end

      def to_addrs
        @to_addrs ||= normalize_list(parsed[:to])
      end

      def cc_addrs
        @cc_addrs ||= normalize_list(parsed[:cc])
      end

      def bcc_addrs
        @bcc_addrs ||= normalize_list(parsed[:bcc])
      end

      def subject
        parsed[:subject].presence
      end

      def html
        parsed[:html].to_s
      end

      # Prefer the plain-text part; fall back to a tag-stripped HTML body.
      def body_text
        return parsed[:text] if parsed[:text].present?
        return nil if html.blank?

        ActionController::Base.helpers.strip_tags(html).gsub(/\n{3,}/, "\n\n").strip.presence
      end

      # Thread the conversation: the first referenced parent (In-Reply-To, then
      # the last id in References) groups replies onto the original; with no
      # references, the message starts its own thread keyed by its Message-ID.
      def thread_id
        parsed[:in_reply_to].to_s.split.first.presence ||
          parsed[:references].to_s.split.last.presence ||
          message_id.presence
      end

      def sent_at
        raw = parsed[:date]
        return raw if raw.is_a?(Time) || raw.is_a?(DateTime)

        Time.zone.parse(raw.to_s) || Time.current
      rescue ArgumentError, TypeError
        Time.current
      end

      def normalize_list(value)
        Array(value).flat_map { |v| v.to_s.split(",") }.map(&:strip).reject(&:blank?)
      end

      def record_audit(event, lead)
        AuditLog.record!(
          action: "inbound_email_recorded",
          subject: lead,
          detail: "#{event.direction} email #{event.subject.inspect} from #{event.from_addr}"
        )
      rescue StandardError => e
        Rails.logger.warn("[Sendoff::InboundEmail::Ingest] audit failed: #{e.class}: #{e.message}")
      end

      def log_unmatched(event)
        Rails.logger.info(
          "[Sendoff::InboundEmail::Ingest] recorded #{event.direction} email #{event.id} " \
          "with no matching lead (from=#{event.from_addr} to=#{event.to_addrs.inspect})"
        )
      end
    end
  end
end
