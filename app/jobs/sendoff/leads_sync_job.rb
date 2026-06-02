module Sendoff
  # Runs the generic warm-lead sync. Schedule this (e.g. daily) in the host app;
  # the engine ships no cron of its own.
  class LeadsSyncJob < ApplicationJob
    def perform
      Sendoff::Leads::Sync.call
    end
  end
end
