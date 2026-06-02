FactoryBot.define do
  factory :note, class: "Sendoff::Note" do
    association :notable, factory: :company
    body_md { "A useful note about this record." }
    author { "system" }

    trait :on_lead do
      association :notable, factory: :lead
    end
  end
end
