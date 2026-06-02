FactoryBot.define do
  factory :email_event, class: "Sendoff::EmailEvent" do
    direction { "outbound" }
    from_addr { "sender@example.com" }
    to_addrs { [ "recipient@example.com" ] }
    subject { "Hello" }
    sent_at { Time.current }

    trait :inbound do
      direction { "inbound" }
      from_addr { "recipient@example.com" }
      to_addrs { [ "sender@example.com" ] }
    end
  end
end
