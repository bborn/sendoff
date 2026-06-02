FactoryBot.define do
  factory :voice_rule, class: "Sendoff::VoiceRule" do
    scope { "all" }
    rule { "Keep it short and avoid jargon." }
    active { true }

    trait :cold_prospect do
      scope { "cold_prospect" }
    end

    trait :inactive do
      active { false }
    end
  end
end
