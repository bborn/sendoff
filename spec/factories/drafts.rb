FactoryBot.define do
  factory :draft, class: "Sendoff::Draft" do
    association :lead
    association :email_account
    to_addr { "recipient@example.com" }
    subject { "Quick question" }
    body_html { "<p>Hello there</p>" }
    status { "pending" }
    intent { "cold" }

    trait :pending do
      status { "pending" }
    end

    trait :sent do
      status { "sent" }
      sent_at { Time.current }
    end

    trait :scheduled do
      status { "scheduled" }
      scheduled_at { 1.hour.from_now }
    end

    trait :flagged do
      status { "flagged" }
      flagged_claims { [ { "claim" => "made up fact", "reason" => "unverifiable" } ] }
    end

    trait :discarded do
      status { "discarded" }
    end

    trait :hallucination_flagged do
      flagged_claims { [ { "claim" => "made up fact" } ] }
    end
  end
end
