FactoryBot.define do
  factory :email_account, class: "Sendoff::EmailAccount" do
    sequence(:email) { |n| "sender#{n}@example.com" }
    display_name { "Dana Sender" }
    role { "outreach" }
    active { true }

    trait :outreach do
      role { "outreach" }
    end

    trait :personal do
      role { "personal" }
    end

    trait :shared do
      role { "shared" }
    end

    trait :inactive do
      active { false }
    end
  end
end
