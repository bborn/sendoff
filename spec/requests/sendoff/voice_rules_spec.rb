require "rails_helper"

RSpec.describe "Sendoff voice rules", type: :request do
  include Sendoff::Engine.routes.url_helpers

  describe "GET /sendoff/voice_rules" do
    it "renders 200 and lists rules" do
      cold = create(:voice_rule, :cold_prospect, rule: "Lead with a question.")
      universal = create(:voice_rule, rule: "Keep it under 120 words.")

      get voice_rules_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Lead with a question.")
      expect(response.body).to include("Keep it under 120 words.")
    end

    it "filters by scope" do
      create(:voice_rule, :cold_prospect, rule: "Cold only rule.")
      create(:voice_rule, rule: "Universal rule.")

      get voice_rules_path(scope: "cold_prospect")

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Cold only rule.")
      expect(response.body).not_to include("Universal rule.")
    end

    it "ignores an unknown scope and shows all rules" do
      create(:voice_rule, rule: "Always present rule.")

      get voice_rules_path(scope: "not_a_scope")

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Always present rule.")
    end
  end

  describe "POST /sendoff/voice_rules" do
    it "creates a rule and writes an audit log" do
      expect {
        post voice_rules_path,
          params: { voice_rule: { scope: "cold_prospect", rule: "No em-dashes." } },
          as: :turbo_stream
      }.to change(Sendoff::VoiceRule, :count).by(1)
        .and change(Sendoff::AuditLog, :count).by(1)

      expect(response).to have_http_status(:ok)
      rule = Sendoff::VoiceRule.order(:created_at).last
      expect(rule.scope).to eq("cold_prospect")
      expect(rule.rule).to eq("No em-dashes.")
      expect(rule.created_by).to be_present

      log = Sendoff::AuditLog.order(:created_at).last
      expect(log.action).to eq("voice_rule_created")
      expect(log.subject).to eq(rule)
    end

    it "returns 422 on invalid input" do
      expect {
        post voice_rules_path,
          params: { voice_rule: { scope: "cold_prospect", rule: "" } },
          as: :turbo_stream
      }.not_to change(Sendoff::VoiceRule, :count)

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "PATCH /sendoff/voice_rules/:id" do
    it "updates a rule's text and scope" do
      rule = create(:voice_rule, scope: "all", rule: "Old text.")

      patch voice_rule_path(rule),
        params: { voice_rule: { scope: "customer_success", rule: "New text." } },
        as: :turbo_stream

      expect(response).to have_http_status(:ok)
      expect(rule.reload.rule).to eq("New text.")
      expect(rule.scope).to eq("customer_success")
    end
  end

  describe "PATCH /sendoff/voice_rules/:id/toggle" do
    it "flips active and writes an audit log" do
      rule = create(:voice_rule, active: true)

      expect {
        patch toggle_voice_rule_path(rule), as: :turbo_stream
      }.to change(Sendoff::AuditLog, :count).by(1)

      expect(response).to have_http_status(:ok)
      expect(rule.reload.active).to be(false)

      patch toggle_voice_rule_path(rule), as: :turbo_stream
      expect(rule.reload.active).to be(true)
    end
  end

  describe "DELETE /sendoff/voice_rules/:id" do
    it "removes the rule and writes an audit log" do
      rule = create(:voice_rule)

      expect {
        delete voice_rule_path(rule), as: :turbo_stream
      }.to change(Sendoff::VoiceRule, :count).by(-1)
        .and change(Sendoff::AuditLog, :count).by(1)

      expect(response).to have_http_status(:ok)
      expect(Sendoff::VoiceRule.where(id: rule.id)).to be_empty
    end
  end
end
