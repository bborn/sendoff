# Real Gmail integration depends on these gems. They are declared in the
# gemspec; required here so the constants resolve when the client is used. The
# FakeClient (tests/demos) has no such dependency.
require "google/apis/gmail_v1"
require "signet/oauth_2/client"
require "mail"

module Sendoff
  module Gmail
    # Thin wrapper over google-apis-gmail_v1 for a single EmailAccount.
    #
    # Honors ENV["GMAIL_DRY_RUN"]="true" (reads return empty/canned, writes are
    # logged or blocked). The internal-recipient filter used by #fetch_recent_sent
    # is configurable: excluded domains come from Sendoff.config (if it exposes
    # `excluded_recipient_domains`), else none.
    class Client
      SCOPES = [ "https://www.googleapis.com/auth/gmail.modify" ].freeze

      attr_reader :account

      def self.dry_run?
        ENV["GMAIL_DRY_RUN"] == "true"
      end

      def initialize(account)
        unless account.is_a?(Sendoff::EmailAccount)
          raise ArgumentError, "expected Sendoff::EmailAccount, got #{account.class}"
        end
        @account = account
      end

      # Domains whose recipients should be excluded from "recent sent" voice
      # sampling (e.g. your own internal team). Generic: pulled from config when
      # available, otherwise empty.
      def self.excluded_recipient_domains
        cfg = Sendoff.config
        return Array(cfg.excluded_recipient_domains) if cfg.respond_to?(:excluded_recipient_domains)
        []
      end

      def search_threads(query:, limit: 20)
        return [] if Client.dry_run?
        threads = []
        page_token = nil
        while threads.size < limit
          resp = service.list_user_threads("me", q: query,
            max_results: [ limit - threads.size, 100 ].min, page_token: page_token)
          Array(resp.threads).each do |t|
            threads << { id: t.id, snippet: t.snippet, history_id: t.history_id }
            break if threads.size >= limit
          end
          page_token = resp.next_page_token
          break unless page_token
        end
        threads
      end

      def thread_summary(thread_id)
        return nil if Client.dry_run?
        t = service.get_user_thread("me", thread_id, format: "metadata",
          metadata_headers: %w[From To Cc Subject Date Message-ID])
        messages = (t.messages || []).reject { |m| Array(m.label_ids).include?("DRAFT") }
        return nil if messages.empty?
        hdr = ->(m, name) { m.payload.headers.find { |h| h.name.casecmp(name).zero? }&.value }
        {
          id: thread_id,
          subject: hdr.call(messages.first, "Subject"),
          participants: messages.map { |m| hdr.call(m, "From") }.compact.uniq,
          messages_count: messages.size,
          first_date: hdr.call(messages.first, "Date"),
          last_date: hdr.call(messages.last, "Date")
        }
      end

      def get_message_body(message_id)
        return "(dry-run)" if Client.dry_run?
        m = service.get_user_message("me", message_id, format: "full")
        extract_text(m.payload)
      end

      def create_draft(to:, subject:, body_html:, cc: nil, bcc: nil, thread_id: nil)
        if Client.dry_run?
          fake_id = "DRYRUN-DRAFT-#{SecureRandom.hex(6)}"
          Rails.logger.info "[Sendoff::Gmail::Client DRY_RUN] create_draft to=#{to} subj=#{subject.inspect} → #{fake_id}"
          return fake_id
        end
        raw = build_mime(to: to, subject: subject, body_html: body_html, cc: cc, bcc: bcc, thread_id: thread_id)
        msg = Google::Apis::GmailV1::Message.new(raw: raw, thread_id: thread_id)
        draft = Google::Apis::GmailV1::Draft.new(message: msg)
        service.create_user_draft("me", draft).id
      end

      def send_message(to:, subject:, body_html:, cc: nil, bcc: nil, thread_id: nil)
        if Client.dry_run?
          Rails.logger.warn "[Sendoff::Gmail::Client DRY_RUN] send_message BLOCKED to=#{to} subj=#{subject.inspect}"
          raise "Gmail dry-run mode: send blocked"
        end
        raw = build_mime(to: to, subject: subject, body_html: body_html, cc: cc, bcc: bcc, thread_id: thread_id)
        msg = Google::Apis::GmailV1::Message.new(raw: raw, thread_id: thread_id)
        service.send_user_message("me", msg).id
      end

      def delete_draft(draft_id)
        return if Client.dry_run?
        service.delete_user_draft("me", draft_id)
      rescue Google::Apis::ClientError => e
        Rails.logger.warn("Sendoff::Gmail::Client#delete_draft #{draft_id}: #{e.message}")
        nil
      end

      def fetch_messages_for(email_address:, limit: 20)
        return [] if Client.dry_run?
        query = "to:#{email_address} OR from:#{email_address}"
        resp  = service.list_user_messages("me", q: query, max_results: limit)
        return [] if resp.messages.blank?
        resp.messages.first(limit).filter_map do |msg_ref|
          fetch_message_metadata(msg_ref.id)
        rescue Google::Apis::Error => e
          Rails.logger.warn "Sendoff::Gmail::Client#fetch_messages_for message #{msg_ref.id}: #{e.message}"
          nil
        end
      end

      def fetch_messages_for_domain(domain:, limit: 10)
        return [] if Client.dry_run?
        query = "to:@#{domain} OR from:@#{domain}"
        resp  = service.list_user_messages("me", q: query, max_results: limit)
        return [] if resp.messages.blank?
        resp.messages.first(limit).filter_map do |msg_ref|
          fetch_message_metadata(msg_ref.id)
        rescue Google::Apis::Error => e
          Rails.logger.warn "Sendoff::Gmail::Client#fetch_messages_for_domain message #{msg_ref.id}: #{e.message}"
          nil
        end
      end

      def search_messages_content(query:, limit: 5)
        return [] if Client.dry_run?
        resp = service.list_user_messages("me", q: query, max_results: limit)
        return [] if resp.messages.blank?
        resp.messages.first(limit).filter_map do |msg_ref|
          body = get_message_body(msg_ref.id)
          meta = fetch_message_metadata(msg_ref.id)
          meta.merge(body: body) if body.present?
        rescue Google::Apis::Error => e
          Rails.logger.warn "Sendoff::Gmail::Client#search_messages_content message #{msg_ref.id}: #{e.message}"
          nil
        end
      end

      # Fetch the body of the last SENT message in a thread (not a draft).
      def fetch_sent_body_from_thread(thread_id)
        return "(dry-run)" if Client.dry_run?
        t = service.get_user_thread("me", thread_id, format: "full")
        sent = (t.messages || []).select { |m|
          labels = Array(m.label_ids)
          labels.include?("SENT") && !labels.include?("DRAFT")
        }
        return nil if sent.empty?
        extract_text(sent.last.payload).presence
      rescue => e
        Rails.logger.warn "Sendoff::Gmail::Client#fetch_sent_body_from_thread #{thread_id}: #{e.message}"
        nil
      end

      # Fetch last N outbound sent messages with subject + body (for voice anchor
      # fallback). Excludes configured internal recipient domains.
      def fetch_recent_sent(limit: 5)
        return [] if Client.dry_run?
        query = "in:sent -to:me"
        Client.excluded_recipient_domains.each { |d| query << " -to:@#{d}" }
        resp = service.list_user_messages("me", q: query, max_results: limit)
        return [] if resp.messages.blank?
        resp.messages.first(limit).filter_map do |msg_ref|
          body = get_message_body(msg_ref.id)
          next if body.blank?
          meta = fetch_message_metadata(msg_ref.id)
          next unless meta[:direction] == "outbound"
          meta.merge(body: body)
        rescue Google::Apis::Error => e
          Rails.logger.warn "Sendoff::Gmail::Client#fetch_recent_sent message #{msg_ref.id}: #{e.message}"
          nil
        end
      end

      private

      def service
        @service ||= begin
          gmail = Google::Apis::GmailV1::GmailService.new
          gmail.authorization = authorization
          gmail
        end
      end

      def authorization
        Signet::OAuth2::Client.new(
          token_credential_uri: "https://oauth2.googleapis.com/token",
          client_id: account.resolved_client_id,
          client_secret: account.resolved_client_secret,
          refresh_token: account.oauth_refresh_token,
          scope: SCOPES
        ).tap(&:fetch_access_token!)
      end

      def fetch_message_metadata(message_id)
        msg = service.get_user_message("me", message_id, format: "metadata",
          metadata_headers: %w[From To Subject Date])
        hdr = ->(name) { msg.payload.headers.find { |h| h.name.casecmp(name).zero? }&.value.to_s }
        from_addr = hdr.call("From")
        {
          id:              message_id,
          subject:         hdr.call("Subject").presence,
          sent_at:         (Time.parse(hdr.call("Date")) rescue nil),
          from:            from_addr,
          to:              hdr.call("To"),
          account_name:    account.display_name,
          account_email:   account.email,
          direction:       from_addr.include?(account.email) ? "outbound" : "inbound",
          gmail_thread_id: msg.thread_id,
          snippet:         msg.snippet.to_s
        }
      end

      def extract_text(payload)
        walk = ->(p, mimetype) do
          if p.body&.data.present? && p.mime_type == mimetype
            data = p.body.data
            # google-apis-gmail_v1 decodes body.data automatically for format:"full".
            # If the string contains non-base64url characters it's already plain text.
            if data.match?(/[^A-Za-z0-9+\/=\-_]/)
              return data.force_encoding("UTF-8").scrub
            end
            begin
              padded = data + "=" * ((4 - data.length % 4) % 4)
              return Base64.urlsafe_decode64(padded).force_encoding("UTF-8").scrub
            rescue ArgumentError
              return data.force_encoding("UTF-8").scrub
            end
          end
          Array(p.parts).each { |sub| r = walk.call(sub, mimetype); return r if r }
          nil
        end
        walk.call(payload, "text/plain") || walk.call(payload, "text/html") || ""
      end

      def build_mime(to:, subject:, body_html:, cc:, bcc:, thread_id:)
        mail = Mail.new
        mail.to = to
        mail.cc = cc if cc
        mail.subject = subject
        mail.from = "#{account.display_name} <#{account.email}>"
        mail.content_type = "text/html; charset=UTF-8"
        mail.body = body_html
        if thread_id
          # These headers keep the draft attached to the right Gmail thread.
          mail.header["In-Reply-To"] = thread_id
          mail.header["References"]  = thread_id
        end
        encoded = mail.to_s
        if bcc.present?
          # Mail#encoded strips Bcc per RFC (right for SMTP, wrong for Gmail's
          # send API, which reads recipients from the raw MIME). Inject Bcc before
          # the body separator.
          encoded = encoded.sub(/\r?\n\r?\n/, "\r\nBcc: #{bcc}\r\n\r\n")
        end
        encoded
      end
    end
  end
end
