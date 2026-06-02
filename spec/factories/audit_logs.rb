FactoryBot.define do
  factory :audit_log, class: "Sendoff::AuditLog" do
    actor { "system" }
    action { "draft.created" }
  end
end
