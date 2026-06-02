# Sendoff demo task — proves the engine runs end-to-end on a generic,
# fully-fictional adapter with NO secrets and NO network.
#
# It configures the bundled Example::LeadSource + the FakeClient LLM, runs the
# generic Leads::Sync, then prints a pipeline summary.
#
# Run it against the dummy app DB (create/migrate first if needed):
#
#   cd /path/to/sendoff/spec/dummy
#   RAILS_ENV=development bin/rails db:create db:migrate
#   cd ../..
#   RAILS_ENV=development bundle exec rake app:sendoff:demo
#
# (The `app:` prefix comes from engine task loading via the dummy app. In a
#  host app that mounts the engine, it's simply `rake sendoff:demo`.)
#
# Idempotent — re-running it will not create duplicate leads.

namespace :sendoff do
  desc "Run the lead-sync demo on the fictional example adapter (no secrets/network)"
  task demo: :environment do
    Sendoff.configure do |c|
      c.lead_source = Sendoff::Adapters::Example::LeadSource.new
      c.llm_client  = Sendoff::LLM::FakeClient.new
    end

    puts "== Sendoff demo =="
    puts "Lead source: #{Sendoff.config.lead_source.class}"
    puts "LLM client:  #{Sendoff.config.llm_client.class}"
    puts

    stats = Sendoff::Leads::Sync.call
    puts "Sync stats: #{stats.map { |k, v| "#{k}=#{v}" }.join(' ')}"
    puts

    stage_order = %w[new drafting review contacted replied dud]
    counts = Sendoff::PipelineEntry.group(:stage).count
    puts "Pipeline by stage:"
    stage_order.each { |s| puts format("  %-10s %d", s, counts[s].to_i) }
    puts

    puts "Companies by segment:"
    Sendoff::Company.group(:segment).count.sort.each do |seg, n|
      puts format("  %-10s %d", seg || "(none)", n)
    end
    puts

    puts "Sample leads (warmest first):"
    rows = Sendoff::PipelineEntry
             .includes(:lead, :company)
             .order(warm_score: :desc)
             .limit(8)
    rows.each do |pe|
      lead = pe.lead
      puts format(
        "  [%-7s] score=%-2d  %-28s  %-22s  %s",
        pe.stage, pe.warm_score, lead.email, lead.display_name, pe.company.segment_label
      )
    end

    puts
    puts "Totals: #{Sendoff::Company.count} companies, " \
         "#{Sendoff::Lead.count} leads, " \
         "#{Sendoff::PipelineEntry.count} pipeline entries."
  end
end
