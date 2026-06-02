module Sendoff
  module Gmail
    # In-memory test/demo double for Gmail::Client. Implements the same method
    # surface, returns empty/canned data by default, and records create_draft /
    # send_message / delete_draft calls so specs can assert on them.
    #
    # Wired in by spec/rails_helper.rb via config.gmail_client_factory, hence the
    # required email_account arg.
    class FakeClient
      attr_reader :account, :created_drafts, :sent_messages, :deleted_drafts

      # Optional canned reads. Override by assigning after construction, e.g.
      #   client = FakeClient.new(account)
      #   client.threads = [{ id: "t1", snippet: "hi", history_id: "1" }]
      attr_accessor :threads, :messages, :recent_sent

      def initialize(account = nil)
        @account        = account
        @created_drafts = []
        @sent_messages  = []
        @deleted_drafts = []
        @threads        = []
        @messages       = []
        @recent_sent    = []
      end

      def self.dry_run?
        false
      end

      def search_threads(query:, limit: 20)
        @threads.first(limit)
      end

      def thread_summary(_thread_id)
        nil
      end

      def get_message_body(_message_id)
        ""
      end

      def fetch_messages_for(email_address:, limit: 20)
        @messages.first(limit)
      end

      def fetch_messages_for_domain(domain:, limit: 10)
        @messages.first(limit)
      end

      def search_messages_content(query:, limit: 5)
        @messages.first(limit)
      end

      def fetch_sent_body_from_thread(_thread_id)
        nil
      end

      def fetch_recent_sent(limit: 5)
        @recent_sent.first(limit)
      end

      def create_draft(to:, subject:, body_html:, cc: nil, bcc: nil, thread_id: nil)
        id = "FAKE-DRAFT-#{@created_drafts.size + 1}"
        @created_drafts << {
          id: id, to: to, subject: subject, body_html: body_html,
          cc: cc, bcc: bcc, thread_id: thread_id
        }
        id
      end

      def send_message(to:, subject:, body_html:, cc: nil, bcc: nil, thread_id: nil)
        id = "FAKE-SENT-#{@sent_messages.size + 1}"
        @sent_messages << {
          id: id, to: to, subject: subject, body_html: body_html,
          cc: cc, bcc: bcc, thread_id: thread_id
        }
        id
      end

      def delete_draft(draft_id)
        @deleted_drafts << draft_id
        nil
      end
    end
  end
end
