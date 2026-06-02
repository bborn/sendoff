FactoryBot.define do
  factory :company, class: "Sendoff::Company" do
    sequence(:name) { |n| "Acme #{n}" }
    sequence(:domain) { |n| "acme#{n}.com" }
    # Default to a brand-ish domain so auto_classify_segment lands on :brand.

    trait :nonprofit do
      sequence(:name) { |n| "Cedarvale Foundation #{n}" }
      sequence(:domain) { |n| "cedarvale#{n}.org" }
    end

    trait :agency do
      sequence(:name) { |n| "Bright Media Agency #{n}" }
      sequence(:domain) { |n| "brightmediaagency#{n}.com" }
    end

    trait :preset_segment do
      segment { "brand" }
    end
  end
end
