FactoryBot.define do
  factory :pipeline_entry, class: "Sendoff::PipelineEntry" do
    lead { association :lead, company: company }
    company

    stage { "new" }
    signals { {} }
    warm_score { 0 }
    reports_viewed { 0 }

    trait :new_stage do
      stage { "new" }
    end

    trait :drafting do
      stage { "drafting" }
    end

    trait :review do
      stage { "review" }
    end

    trait :contacted do
      stage { "contacted" }
    end

    trait :replied do
      stage { "replied" }
    end

    trait :dud do
      stage { "dud" }
    end

    trait :warm do
      warm_score { 3 }
      signals { { "warm_account" => true } }
    end
  end
end
