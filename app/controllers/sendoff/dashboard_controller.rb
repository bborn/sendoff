module Sendoff
  class DashboardController < ApplicationController
    def index
      @counts = PipelineEntry.group(:stage).count
      @drafts_to_review = Draft.where(status: "pending").order(created_at: :desc).limit(10)
      @recent_leads = Lead.order(created_at: :desc).limit(10)
    end
  end
end
