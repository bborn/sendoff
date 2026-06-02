module Sendoff
  module ApplicationHelper
    # The product name shown in the nav/title. Defaults to the configured
    # persona's product name, falling back to "Sendoff".
    def app_name
      Sendoff.config.persona.product_name.presence || "Sendoff"
    end

    # Relative time, e.g. "3d ago".
    def time_ago_short(time)
      return "" unless time
      "#{time_ago_in_words(time)} ago"
    end
  end
end
