require "rails_helper"

module Sendoff
  RSpec.describe AuditLog, type: :model do
    after { Current.reset }

    it "has a valid factory" do
      expect(build(:audit_log)).to be_valid
    end

    describe ".record!" do
      it "defaults the actor to system when none is set" do
        log = AuditLog.record!(action: "draft.created")
        expect(log.actor).to eq("system")
        expect(log.action).to eq("draft.created")
      end

      it "uses Current.actor when present" do
        Current.actor = "agent:internal"
        log = AuditLog.record!(action: "draft.sent")
        expect(log.actor).to eq("agent:internal")
      end

      it "records the polymorphic subject" do
        lead = create(:lead)
        log = AuditLog.record!(action: "lead.touched", subject: lead)
        expect(log.subject).to eq(lead)
      end
    end
  end
end
