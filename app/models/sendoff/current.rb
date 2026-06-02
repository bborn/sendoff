module Sendoff
  # Request/job-scoped actor for audit logging. Generic: holds a string actor
  # (e.g. "agent:internal", an email, or nil). No User record dependency.
  class Current < ActiveSupport::CurrentAttributes
    attribute :actor

    # The audit log wants a non-blank string. Prefer an explicitly set actor,
    # then fall back to "system".
    def actor_or_system
      actor.presence || "system"
    end
  end
end
