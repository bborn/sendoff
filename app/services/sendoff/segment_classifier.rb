module Sendoff
  # Pure-Ruby heuristic segment classifier. No LLM calls, no network.
  #
  # Takes a Company record and an optional research summary string and returns
  # one of the generic example segments: :agency, :brand, :nonprofit, :unknown.
  #
  #   SegmentClassifier.classify(company)              # => :brand
  #   SegmentClassifier.classify_with_reason(company)  # => [:brand, "brand_default"]
  #
  # NOTE(seam): the keyword sets below are example heuristics. Hosts with a
  # different taxonomy can replace this classifier wholesale; Company only
  # depends on the two class methods.
  class SegmentClassifier
    AGENCY_DOMAIN_KEYWORDS = %w[agency media marketing studio partners collective consulting creative].freeze
    AGENCY_NAME_PATTERN    = /\b(agency|agencies|media|marketing|studio|partners|collective|consulting|creative)\b/i
    AGENCY_SUMMARY_PATTERN = /\b(marketing agency|creative agency|media agency|consulting firm|consultancy)\b/i

    NONPROFIT_DOMAIN_KEYWORDS = %w[foundation association nonprofit institute alliance coalition].freeze
    NONPROFIT_DOMAIN_TLD      = /\.org$/
    NONPROFIT_NAME_PATTERN    = /\b(foundation|association|nonprofit|non-profit|institute|alliance|coalition)\b/i
    NONPROFIT_SUMMARY_PATTERN = /\b(nonprofit|non-profit|charity|501\(c\)|foundation|association)\b/i

    def self.classify(company, summary: nil)
      new(company, summary: summary).segment
    end

    def self.classify_with_reason(company, summary: nil)
      c = new(company, summary: summary)
      [ c.segment, c.reason ]
    end

    def initialize(company, summary: nil)
      @company = company
      @domain  = company.domain.to_s.strip.downcase
      @name    = company.name.to_s.strip
      @summary = summary.to_s
    end

    def segment
      _determine.first
    end

    def reason
      _determine.last
    end

    private

    def _determine
      @_determine ||= compute
    end

    def compute
      # Nonprofit is checked before agency so an ".org" association/institute
      # doesn't get swept into the agency bucket by a stray keyword.
      result = if blank_signal?
        [ :unknown, "no_signal" ]
      elsif nonprofit?
        [ :nonprofit, nonprofit_reason ]
      elsif agency?
        [ :agency, agency_reason ]
      else
        [ :brand, "brand_default" ]
      end
      Rails.logger.info "[Sendoff::SegmentClassifier] domain=#{@domain} segment=#{result[0]} reason=#{result[1]}"
      result
    end

    def blank_signal?
      @domain.blank? && @name.blank? && @summary.blank?
    end

    def agency?
      domain_has_agency_keyword? || name_has_agency_signal? || summary_mentions_agency?
    end

    def nonprofit?
      domain_has_nonprofit_keyword? || domain_has_nonprofit_tld? || name_has_nonprofit_signal? || summary_mentions_nonprofit?
    end

    def domain_has_agency_keyword?
      AGENCY_DOMAIN_KEYWORDS.any? { |kw| @domain.include?(kw) }
    end

    def name_has_agency_signal?
      AGENCY_NAME_PATTERN.match?(@name)
    end

    def summary_mentions_agency?
      @summary.present? && AGENCY_SUMMARY_PATTERN.match?(@summary)
    end

    def domain_has_nonprofit_keyword?
      NONPROFIT_DOMAIN_KEYWORDS.any? { |kw| @domain.include?(kw) }
    end

    def domain_has_nonprofit_tld?
      NONPROFIT_DOMAIN_TLD.match?(@domain)
    end

    def name_has_nonprofit_signal?
      NONPROFIT_NAME_PATTERN.match?(@name)
    end

    def summary_mentions_nonprofit?
      @summary.present? && NONPROFIT_SUMMARY_PATTERN.match?(@summary)
    end

    def agency_reason
      if domain_has_agency_keyword?
        kw = AGENCY_DOMAIN_KEYWORDS.find { |k| @domain.include?(k) }
        "agency_domain_keyword:#{kw}"
      elsif name_has_agency_signal?
        "agency_name_signal"
      else
        "agency_summary"
      end
    end

    def nonprofit_reason
      if domain_has_nonprofit_keyword?
        kw = NONPROFIT_DOMAIN_KEYWORDS.find { |k| @domain.include?(k) }
        "nonprofit_domain_keyword:#{kw}"
      elsif domain_has_nonprofit_tld?
        "nonprofit_domain_tld"
      elsif name_has_nonprofit_signal?
        "nonprofit_name_signal"
      else
        "nonprofit_summary"
      end
    end
  end
end
