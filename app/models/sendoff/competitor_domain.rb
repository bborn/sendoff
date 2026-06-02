module Sendoff
  class CompetitorDomain < ApplicationRecord
    CATEGORIES = %w[direct adjacent monetization ai_competitor].freeze

    validates :domain, presence: true, uniqueness: { case_sensitive: false }
    validates :category, presence: true, inclusion: { in: CATEGORIES }

    before_validation :normalize_domain

    private

    def normalize_domain
      self.domain = domain.to_s.downcase.strip
    end
  end
end
