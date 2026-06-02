module Sendoff
  class Drafter
    # Supplies recent, real, on-voice example sends for a given EmailAccount so
    # the Drafter prompt can anchor on how this sender actually writes.
    #
    # Prefers the engine's own sent Drafts (most accurate signal); falls back to
    # the account's Gmail sent folder via config.gmail_client_for(account).
    class VoiceAnchor
      CACHE_TTL       = 60.seconds
      GMAIL_CACHE_TTL = 5.minutes
      MIN_SENDOFF_DRAFTS  = 3

      def self.for_sender(email_account, segment: nil)
        cache_key = "sendoff_voice_anchor:#{email_account.id}:#{segment}"
        Rails.cache.fetch(cache_key, expires_in: CACHE_TTL) do
          new(email_account, segment: segment).call
        end
      end

      def initialize(email_account, segment: nil)
        @email_account = email_account
        @segment = segment
      end

      def call
        sdr = sdr_examples
        return sdr if sdr.size >= MIN_SENDOFF_DRAFTS

        # Not enough engine sends yet — fall back to Gmail sent folder.
        gmail_examples
      end

      def sdr_examples
        scope = Draft
          .where(status: "sent", email_account: @email_account)
          .where.not(sent_at: nil)
          .order(sent_at: :desc)

        if @segment.present?
          scope = scope.joins(lead: :company).where(sendoff_companies: { segment: @segment })
        end

        scope.limit(5).map do |d|
          {
            subject: d.subject,
            body_html: strip_signature(d.body_html)
          }
        end
      end

      def gmail_examples
        Rails.cache.fetch("sendoff_voice_anchor_gmail:#{@email_account.id}", expires_in: GMAIL_CACHE_TTL) do
          fetch_gmail_examples
        end
      end

      private

      def fetch_gmail_examples
        msgs = Sendoff.config.gmail_client_for(@email_account).fetch_recent_sent(limit: 5)
        msgs.map do |m|
          {
            subject: m[:subject].to_s,
            body_html: strip_signature_text(m[:body].to_s)
          }
        end
      rescue => e
        Rails.logger.warn "[Sendoff::Drafter::VoiceAnchor] Gmail fallback error for #{@email_account.email}: #{e.message}"
        []
      end

      def strip_signature(html)
        return html.to_s if html.blank?
        result = html.dup
        result = result.gsub(/<p[^>]*>\s*(?:Thanks|Best|Cheers|Regards)[,.]?[\s\S]*\z/im, "")
        result = result.gsub(/\n\s*(?:Thanks|Best|Cheers|Regards)[,.][\s\S]*\z/im, "")
        result.strip
      rescue
        html.to_s
      end

      def strip_signature_text(text)
        return text.to_s if text.blank?
        text.gsub(/\n\s*(?:Thanks|Best|Cheers|Regards)[,.][\s\S]*\z/im, "").strip
      rescue
        text.to_s
      end
    end
  end
end
