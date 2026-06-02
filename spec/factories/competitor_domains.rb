FactoryBot.define do
  factory :competitor_domain, class: "Sendoff::CompetitorDomain" do
    sequence(:domain) { |n| "competitor#{n}.com" }
    category { "direct" }
    reason { "Head-to-head competitor." }
  end
end
