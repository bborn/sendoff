module Sendoff
  class Drafter
    # Assembles the full context hash the Drafter and its critics need: lead +
    # company facts, account/customer lookup, Gmail thread history (per-lead and
    # per-domain), notes, voice rules, voice examples, and brand-mention counts.
    #
    # All host-specific data flows through config seams:
    #   - account info     -> Sendoff.config.account_lookup.find(lead)
    #   - brand mentions   -> Sendoff.config.brand_mention_source.count_for(company)
    #   - gmail history     -> Sendoff::Gmail::History (config.gmail_client_for)
    class Context
      INTENT_TO_VOICE_SCOPE = {
        cold: "cold_prospect",
        reengage: "reengage_cold",
        checkin: "reengage_customer",
        followup: "reengage_customer"
      }.freeze

      def initialize(lead, intent:)
        @lead = lead
        @intent = intent.to_sym
      end

      def build
        threads = thread_history_data
        {
          intent: @intent,
          lead: lead_data,
          company: company_data,
          account: account_data,
          reports_viewed: reports_viewed_data,
          thread_history: threads,
          domain_thread_history: domain_thread_history_data(threads),
          days_since_last_contact: days_since_last_contact(threads),
          company_notes: company_notes_data,
          research_summary: research_summary_data,
          voice_rules: voice_rules_text,
          voice_examples: voice_examples_data,
          brand_mentions_count: brand_mentions_count_data
        }
      end

      private

      def lead_data
        {
          email: @lead.email,
          first_name: @lead.first_name.to_s,
          full_name: @lead.full_name.to_s,
          name_source: @lead.name_source.to_s
        }
      end

      def company_data
        c = @lead.company
        {
          name: c&.name,
          domain: c&.domain,
          segment: c&.segment.to_s
        }
      end

      # AccountInfo | nil from the host's account_lookup adapter. Replaces the
      # host's user -> account -> subscription lookup in the original app.
      def account_data
        return @account_data if defined?(@account_data)
        @account_data = Sendoff.config.account_lookup.find(@lead)
      end

      def reports_viewed_data
        pe = pipeline_entry
        return [] unless pe&.reports_viewed.to_i > 0
        [ { count: pe.reports_viewed, viewed_at: pe.last_report_view } ]
      end

      # Returns thread history grouped by sending email_account, so the drafter
      # can pick the right account to draft as (the one with prior history).
      def thread_history_data
        @thread_history_data ||= begin
          hist = Sendoff::Gmail::History.for_lead(@lead) rescue { messages: [] }
          messages = hist[:messages] || []

          if messages.empty?
            []
          else
            messages.group_by { |m| [ m[:gmail_thread_id], m[:account_email] ] }
                    .map do |(thread_id, account_email), msgs|
                      {
                        id: thread_id,
                        account_email: account_email,
                        account_name: msgs.first[:account_name],
                        subject: msgs.first[:subject],
                        last_date: msgs.map { |m| m[:sent_at] }.compact.max&.to_date&.to_s,
                        messages: msgs.size
                      }
                    end
                    .sort_by { |t| t[:last_date].to_s }.reverse
                    .first(10)
          end
        end
      end

      # Domain-wide thread history: conversations with anyone at the same domain,
      # excluding threads already captured in thread_history_data (exact lead match).
      def domain_thread_history_data(lead_threads)
        domain = @lead.company&.domain.presence || @lead.email.to_s.split("@", 2).last&.downcase
        return [] unless domain.present?

        hist = Sendoff::Gmail::History.for_domain(domain) rescue { messages: [] }
        messages = hist[:messages] || []
        return [] if messages.empty?

        lead_thread_ids = lead_threads.map { |t| t[:id] }.to_set

        messages
          .reject { |m| lead_thread_ids.include?(m[:gmail_thread_id]) }
          .group_by { |m| [ m[:gmail_thread_id], m[:account_email] ] }
          .map do |(thread_id, account_email), msgs|
            {
              id: thread_id,
              account_email: account_email,
              account_name: msgs.first[:account_name],
              subject: msgs.first[:subject],
              from: msgs.first[:from],
              last_date: msgs.map { |m| m[:sent_at] }.compact.max&.to_date&.to_s,
              messages: msgs.size
            }
          end
          .sort_by { |t| t[:last_date].to_s }.reverse
          .first(10)
      end

      def days_since_last_contact(threads)
        last_date_str = threads.first&.dig(:last_date)
        return nil unless last_date_str.present?
        (Date.today - Date.parse(last_date_str)).to_i
      rescue
        nil
      end

      def company_notes_data
        return [] unless @lead.company
        Note
          .where(notable: @lead.company)
          .order(created_at: :desc)
          .limit(5)
          .map { |n| { title: n.title.to_s, content: n.body_md.to_s.first(1200), created_at: n.created_at.to_s } }
      end

      # Returns the body_md of the most recent substantial note (> 300 chars) on
      # the lead or their company. Used to inject pre-researched context.
      def research_summary_data
        note = Note.where(notable: @lead).order(created_at: :desc).first
        return note.body_md if note&.body_md&.length.to_i > 300

        if @lead.company
          note = Note.where(notable: @lead.company).order(created_at: :desc).first
          return note.body_md if note&.body_md&.length.to_i > 300
        end

        nil
      end

      def voice_rules_text
        if @intent == :auto
          # For auto intent, include all "all"-scoped rules; intent-specific rules
          # live inside the INTENT_INSTRUCTIONS blocks the LLM will see.
          rules = VoiceRule.where(active: true, scope: "all").pluck(:rule)
        else
          scope_name = INTENT_TO_VOICE_SCOPE.fetch(@intent, "all")
          rules = VoiceRule.where(active: true, scope: [ "all", scope_name ]).pluck(:rule)
        end
        rules.map { |r| "- #{r}" }.join("\n")
      end

      def voice_examples_data
        segment = @lead.company&.segment

        # Mirror Drafter#pick_email_account: prefer account with prior history.
        prior_account_email = thread_history_data.first&.dig(:account_email)
        account = if prior_account_email.present?
          EmailAccount.active.find_by("LOWER(email) = ?", prior_account_email.downcase)
        end
        account ||= EmailAccount.for_outreach.order(:created_at).first

        return [] unless account
        Sendoff::Drafter::VoiceAnchor.for_sender(account, segment: segment)
      rescue => e
        Rails.logger.warn "[Sendoff::Drafter::Context] voice_examples_data error: #{e.message}"
        []
      end

      def brand_mentions_count_data
        Sendoff.config.brand_mention_source.count_for(@lead.company)
      end

      def pipeline_entry
        @pipeline_entry ||= PipelineEntry.where(lead: @lead).order(updated_at: :desc).first
      end
    end
  end
end
