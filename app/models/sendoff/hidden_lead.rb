module Sendoff
  class HiddenLead < ApplicationRecord
    belongs_to :lead

    validates :lead_id, uniqueness: true
  end
end
