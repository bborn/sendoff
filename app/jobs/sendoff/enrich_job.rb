module Sendoff
  # Async lead enrichment. Delegates the actual research to the configured
  # research adapter (Sendoff.config.research_adapter) — the only dependency.
  # With the default NullResearch adapter this is a harmless no-op, so the
  # engine (and lead sync) stay network-free out of the box.
  #
  # When the adapter returns a markdown summary, the job:
  #   - saves it as a "Research Summary (auto)" Note on the lead,
  #   - reclassifies the company's segment if it's currently nil/"unknown"
  #     (manually-set segments are never overwritten),
  #   - records a "lead_enriched" AuditLog entry.
  class EnrichJob < Sendoff::ApplicationJob
    queue_as :default

    # Cap concurrent enrichment when the queue backend supports it (e.g.
    # SolidQueue). The dummy/test adapter doesn't implement limits_concurrency,
    # so we guard the call and degrade gracefully where it's unavailable.
    if respond_to?(:limits_concurrency)
      limits_concurrency key: "sendoff_enrich", to: 1, duration: 10.minutes
    end

    def perform(lead_id, force: false)
      lead = Sendoff::Lead.find_by(id: lead_id)
      return unless lead

      if !force && !lead.enrichable?
        Rails.logger.info "[Sendoff::EnrichJob] lead=#{lead.email} no longer enrichable — skipping"
        return
      end
      Rails.logger.info "[Sendoff::EnrichJob] FORCE re-enrichment for lead=#{lead.email}" if force

      company = lead.company
      summary = Sendoff.config.research_adapter.research(lead)

      if summary.blank?
        Rails.logger.info "[Sendoff::EnrichJob] no research for lead=#{lead.email} (#{Sendoff.config.research_adapter.class}) — no-op"
        return
      end

      Sendoff::Note.create!(
        notable: lead,
        title: "Research Summary (auto)",
        body_md: summary,
        author: "enrich_job",
        source: "llm"
      )

      # Reclassify only when the segment is currently unset/unknown, so a
      # manually-set or source-supplied segment is never overwritten.
      if company && (company.segment.nil? || company.segment == "unknown")
        seg, reason = Sendoff::SegmentClassifier.classify_with_reason(company, summary: summary)
        company.update_columns(segment: seg.to_s, segment_source: "enrich:#{reason}", updated_at: Time.current)
      end

      Sendoff::AuditLog.record!(
        action: "lead_enriched",
        subject: lead,
        recipient: lead.email,
        detail: "note created (#{summary.length} chars); segment=#{company&.segment}"
      )

      Rails.logger.info "[Sendoff::EnrichJob] done lead=#{lead.email} chars=#{summary.length} segment=#{company&.segment}"
    rescue => e
      Rails.logger.error "[Sendoff::EnrichJob] FAILED lead_id=#{lead_id}: #{e.message}"
      raise
    end
  end
end
