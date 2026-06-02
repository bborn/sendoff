require "set"

module Sendoff
  module Replies
    # Find real replies to our outbound emails in the last N days.
    # "Real" = inbound Gmail message in OUR outbound thread, after our send,
    # NOT an auto-reply (OOO / vacation responder / etc).
    #
    # Outbound context comes from Sendoff::EmailEvent (our recorded sends);
    # inbound context + late Gmail-direct outbound come from
    # Sendoff::Gmail::History.for_lead (fake-able in tests).
    class Recent
      AUTO_REPLY_PATTERNS = [
        /\AAutomatic reply:/i,
        /\AAuto[-\s]?reply:/i,
        /\AOut of office\b/i,
        /\AOOO\b/i,
        /\AVacation responder\b/i,
        /\bI am (currently )?out of (the )?office\b/i,
        /\bcurrently on leave\b/i,
        /\bcurrently away from\b/i,
        /\bwill be out of (the )?office\b/i,
        /\bI'?ll be (out|away) (of|from)/i,
        /\bThank you for your (e?-?mail|message),? .* (will be|out|away|absent)/i
      ].freeze

      def self.call(days: 14)
        new(days: days).call
      end

      def initialize(days: 14)
        @days = days
      end

      def call
        sent_events = EmailEvent.where(direction: "outbound")
                                .where("sent_at > ?", @days.days.ago)
                                .where.not(gmail_thread_id: nil)
                                .order(sent_at: :desc)
                                .includes(:lead)
                                .to_a

        by_lead = {}
        sent_events.each do |ee|
          next unless ee.lead
          by_lead[ee.lead_id] ||= { lead: ee.lead, our_thread_ids: Set.new, our_last_sent: ee.sent_at, last_subject: ee.subject }
          by_lead[ee.lead_id][:our_thread_ids] << ee.gmail_thread_id
          if ee.sent_at > by_lead[ee.lead_id][:our_last_sent]
            by_lead[ee.lead_id][:our_last_sent] = ee.sent_at
            by_lead[ee.lead_id][:last_subject]  = ee.subject
          end
        end

        replies = []
        by_lead.each do |_, info|
          history = Sendoff::Gmail::History.for_lead(info[:lead]) rescue { messages: [] }
          msgs = history[:messages] || []

          # Account for outbound replies sent directly via Gmail (outside the
          # send_draft flow). Those don't create EmailEvents, so EmailEvent alone
          # gives a stale "our_last_sent" and inbound messages we already replied
          # to keep showing up as needing a response.
          latest_gmail_outbound = msgs
            .select { |m| m[:direction].to_s == "outbound" && m[:sent_at].present? }
            .map    { |m| m[:sent_at] }
            .max

          if latest_gmail_outbound && latest_gmail_outbound > info[:our_last_sent]
            info[:our_last_sent] = latest_gmail_outbound
          end

          real = msgs.find do |m|
            next false unless m[:direction].to_s == "inbound"
            next false unless m[:sent_at].present? && m[:sent_at] > info[:our_last_sent]
            next false unless info[:our_thread_ids].include?(m[:gmail_thread_id])
            next false if auto_reply?(m)
            true
          end
          next unless real

          replies << {
            lead_id:     info[:lead].id,
            lead_email:  info[:lead].email,
            lead_name:   info[:lead].display_name,
            company:     info[:lead].company&.name,
            subject:     real[:subject] || info[:last_subject],
            snippet:     real[:body_text].to_s.first(300),
            replied_at:  real[:sent_at],
            our_last_sent_at: info[:our_last_sent],
            gmail_thread_url: "https://mail.google.com/mail/u/0/#all/#{real[:gmail_thread_id]}"
          }
        end

        replies.sort_by! { |r| r[:replied_at] || Time.at(0) }.reverse!
        replies
      end

      private

      def auto_reply?(msg)
        subject = msg[:subject].to_s
        body    = msg[:body_text].to_s
        return true if AUTO_REPLY_PATTERNS.any? { |p| subject.match?(p) }
        return true if AUTO_REPLY_PATTERNS.any? { |p| body[0, 200].match?(p) }
        false
      end
    end
  end
end
