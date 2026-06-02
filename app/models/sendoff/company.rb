module Sendoff
  class Company < ApplicationRecord
    # Generic example segments. Hosts can reinterpret these via the
    # SegmentClassifier; the values themselves carry no host-specific meaning.
    # allow_nil so a freshly-built Company validates before auto_classify_segment
    # fills the segment in the after_create hook.
    enum :segment, { agency: "agency", brand: "brand", nonprofit: "nonprofit", unknown: "unknown" },
         validate: { allow_nil: true }

    has_many :leads, dependent: :destroy
    has_many :pipeline_entries, dependent: :destroy
    has_many :email_events, dependent: :nullify
    has_many :notes, as: :notable, dependent: :destroy

    validates :name, presence: true
    validates :domain, presence: true, uniqueness: true

    after_create :auto_classify_segment

    def segment_label
      segment&.titleize || "Unknown"
    end

    private

    def auto_classify_segment
      return unless segment.nil? || segment == "unknown"
      seg, reason = SegmentClassifier.classify_with_reason(self)
      update_columns(segment: seg.to_s, segment_source: "auto:#{reason}", updated_at: Time.current)
    end
  end
end
