module Sendoff
  module Leads
    # Generic warm-lead sync. Pulls normalized LeadData from the configured
    # lead source (Sendoff.config.lead_source.fetch) and upserts the engine's
    # own Company / Lead / PipelineEntry records. Idempotent — safe to re-run.
    #
    #   Sendoff::Leads::Sync.call
    #
    # For each LeadData it will, unless the email is on a personal/free-email
    # skiplist:
    #   - find/create a Company by domain (segment auto-classified, or seeded
    #     from LeadData.segment when the source provides a hint),
    #   - find/create a Lead by email (name derived from LeadData name fields,
    #     falling back to the email local-part with name_source set accordingly),
    #   - find/create a PipelineEntry at stage :new, storing warmth indicators in
    #     the `signals` jsonb and a computed `warm_score`. On re-run the stage is
    #     never touched (that's owned by the SDR workflow) — only the activity
    #     signals are refreshed.
    #
    # Enrichment is intentionally out of scope here (no EnrichJob).
    class Sync
      # Free / personal email providers we never want to prospect into. A lead
      # whose domain is on this list is skipped entirely. Hosts can extend this
      # via their own LeadSource (e.g. by not yielding such addresses).
      PERSONAL_EMAIL_DOMAINS = %w[
        gmail.com googlemail.com yahoo.com ymail.com hotmail.com outlook.com
        live.com msn.com aol.com icloud.com me.com mac.com proton.me
        protonmail.com gmx.com mail.com zoho.com hey.com fastmail.com
        example.com test.com
      ].to_set.freeze

      def self.call
        new.call
      end

      def call
        leads = Array(Sendoff.config.lead_source.fetch)
        Rails.logger.info "[Sendoff::Leads::Sync] #{leads.size} lead(s) from #{Sendoff.config.lead_source.class}"

        stats = { created: 0, updated: 0, skipped: 0, errors: 0 }

        leads.each do |data|
          if skip?(data)
            stats[:skipped] += 1
            next
          end

          process(data, stats)
        rescue => e
          Rails.logger.error "[Sendoff::Leads::Sync] ERROR email=#{data&.email}: #{e.class}: #{e.message}"
          stats[:errors] += 1
        end

        Rails.logger.info "[Sendoff::Leads::Sync] done. #{stats.map { |k, v| "#{k}=#{v}" }.join(' ')}"
        stats
      end

      private

      def skip?(data)
        email = data.email.to_s.strip.downcase
        return true if email.blank? || !email.include?("@")
        PERSONAL_EMAIL_DOMAINS.include?(domain_of(email))
      end

      def process(data, stats)
        company = upsert_company(data)
        lead    = upsert_lead(data, company)
        upsert_pipeline_entry(data, company, lead, stats)
      end

      def upsert_company(data)
        domain  = domain_of(data.email)
        company = Sendoff::Company.find_or_initialize_by(domain: domain)

        if company.new_record?
          company.name = data.company_name.presence || domain
          # If the source supplied a segment hint, honor it and skip the
          # auto-classify (Company only auto-classifies when segment is blank).
          company.segment = data.segment.to_s if data.segment.present?
          company.save!
        end

        company
      end

      def upsert_lead(data, company)
        email = data.email.to_s.strip.downcase
        lead  = Sendoff::Lead.find_or_initialize_by(email: email)

        if lead.new_record?
          lead.company = company
          apply_name(lead, data, email)
          lead.save!
        end

        lead
      end

      # Derive the lead's name from the source's name fields when present,
      # otherwise from the email local-part. name_source records which path won.
      def apply_name(lead, data, email)
        if data.full_name.present? || data.first_name.present? || data.last_name.present?
          first = data.first_name.presence
          last  = data.last_name.presence
          full  = data.full_name.presence || [ first, last ].compact.join(" ").presence

          # Backfill first/last from full_name when the source only gave full.
          if first.nil? && full.present?
            parts = full.split(" ", 2)
            first = parts[0]
            last ||= parts[1]
          end

          lead.first_name  = first
          lead.last_name   = last
          lead.full_name   = full
          lead.name_source = "enriched"
        else
          prefix = email.split("@").first.to_s.gsub(/[._]/, " ").split.map(&:capitalize).join(" ")
          parts  = prefix.split(" ", 2)
          lead.first_name  = parts[0]
          lead.last_name   = parts[1]
          lead.full_name   = prefix.presence
          lead.name_source = "email_prefix"
        end
      end

      def upsert_pipeline_entry(data, company, lead, stats)
        signals = normalize_signals(data.signals)
        score   = warm_score(signals)
        activity = {
          signals:          signals,
          reports_viewed:   signals["reports_viewed"].to_i,
          last_report_view: last_view_date(signals),
          warm_score:       score
        }

        created = false
        entry = Sendoff::PipelineEntry.find_or_initialize_by(lead: lead)
        if entry.new_record?
          entry.company = company
          entry.stage   = "new"
          entry.assign_attributes(activity)
          entry.save!
          created = true
        else
          # Refresh activity signals only — NEVER touch the stage. Stage moves
          # are owned by the SDR workflow (DraftJob/DeliverJob/manual kanban).
          entry.update!(activity)
        end

        stats[created ? :created : :updated] += 1
        entry
      end

      # Generic warm score from free-form signals. Documented, host-agnostic.
      # Higher = warmer. Keys are conventional, all optional:
      #   reports_viewed : distinct assets the lead opened
      #   total_views    : raw open/view count
      #   last_viewed_at : recency (Date/Time/ISO string)
      #
      # Scoring (max 8):
      #   +3  reports_viewed >= 3        (engaged with multiple assets)
      #   +2  reports_viewed >= 5        (heavily engaged)
      #   +1  total_views    >= 10       (lots of raw activity)
      #   +2  viewed within the last 7 days  (hot)
      #   +1  viewed within the last 2 days  (very hot — stacks with above)
      def warm_score(signals)
        reports = signals["reports_viewed"].to_i
        views   = signals["total_views"].to_i
        days    = days_since_last_view(signals)

        score = 0
        score += 3 if reports >= 3
        score += 2 if reports >= 5
        score += 1 if views   >= 10
        if days
          score += 2 if days <= 7
          score += 1 if days <= 2
        end
        score
      end

      def normalize_signals(raw)
        return {} unless raw.is_a?(Hash)
        raw.each_with_object({}) { |(k, v), h| h[k.to_s] = v }
      end

      def last_view_date(signals)
        last_view_value(signals)&.to_date
      rescue ArgumentError, TypeError
        nil
      end

      def days_since_last_view(signals)
        date = last_view_date(signals)
        return nil unless date
        (Date.current - date).to_i
      end

      def last_view_value(signals)
        raw = signals["last_viewed_at"] || signals["last_report_view"]
        return nil if raw.blank?
        raw.is_a?(String) ? Date.parse(raw) : raw
      rescue ArgumentError, TypeError
        nil
      end

      def domain_of(email)
        email.to_s.split("@", 2).last.to_s.strip.downcase
      end
    end
  end
end
