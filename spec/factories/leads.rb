FactoryBot.define do
  factory :lead, class: "Sendoff::Lead" do
    association :company
    sequence(:email) { |n| "lead#{n}@example.com" }
    first_name { "Jordan" }
    last_name { "Rivera" }
    full_name { "Jordan Rivera" }
    name_source { "email_prefix" }
    role { "Marketing Lead" }
  end
end
