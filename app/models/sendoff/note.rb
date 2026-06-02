module Sendoff
  class Note < ApplicationRecord
    belongs_to :notable, polymorphic: true

    validates :body_md, presence: true
  end
end
