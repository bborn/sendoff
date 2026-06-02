require "rails_helper"

module Sendoff
  RSpec.describe VoiceRule, type: :model do
    it "has a valid factory" do
      expect(build(:voice_rule)).to be_valid
    end

    describe "validations" do
      it "requires a rule" do
        expect(build(:voice_rule, rule: nil)).not_to be_valid
      end

      it "requires a scope in SCOPES" do
        expect(build(:voice_rule, scope: "nonsense")).not_to be_valid
        expect(build(:voice_rule, scope: "cold_prospect")).to be_valid
      end
    end

    describe "scopes" do
      it "active_rules returns only active rules" do
        active = create(:voice_rule)
        create(:voice_rule, :inactive)
        expect(VoiceRule.active_rules).to contain_exactly(active)
      end

      it "for_scope filters by scope" do
        cold = create(:voice_rule, :cold_prospect)
        create(:voice_rule, scope: "all")
        expect(VoiceRule.for_scope("cold_prospect")).to contain_exactly(cold)
      end
    end
  end
end
