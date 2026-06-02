module Sendoff
  class CompaniesController < ApplicationController
    PER_PAGE = 50

    # GET /companies — browse table with segment / search filters and
    # leads / pipeline counts.
    def index
      scope = filter_scope

      @total = scope.count
      @page  = [ params[:page].to_i, 1 ].max
      @companies = scope
                     .select(
                       "sendoff_companies.*",
                       "(SELECT COUNT(*) FROM sendoff_leads WHERE sendoff_leads.company_id = sendoff_companies.id) AS leads_count",
                       "(SELECT COUNT(*) FROM sendoff_pipeline_entries WHERE sendoff_pipeline_entries.company_id = sendoff_companies.id) AS pipeline_count"
                     )
                     .order("sendoff_companies.name ASC")
                     .limit(PER_PAGE)
                     .offset((@page - 1) * PER_PAGE)
                     .to_a

      @has_prev = @page > 1
      @has_next = (@page * PER_PAGE) < @total
    end

    # GET /companies/:id — company detail plus its leads.
    def show
      @company = Company.find(params[:id])
      @leads   = @company.leads.includes(:pipeline_entries).order("sendoff_leads.created_at DESC")
      @pipeline_count = @company.pipeline_entries.count
      @notes = @company.notes.order(created_at: :desc)
    end

    private

    def filter_scope
      scope = Company.all
      segment = params[:segment].to_s
      query   = params[:q].to_s.strip

      scope = scope.where(segment: segment) if segment.present? && Company.segments.key?(segment)

      if query.present?
        q = "%#{query.downcase}%"
        scope = scope.where("LOWER(name) LIKE :q OR LOWER(domain) LIKE :q", q: q)
      end

      scope
    end
  end
end
