FactoryBot.define do
  factory :hidden_lead, class: "Sendoff::HiddenLead" do
    association :lead
    hidden_by { "system" }
    reason { "Not a fit." }
  end
end
