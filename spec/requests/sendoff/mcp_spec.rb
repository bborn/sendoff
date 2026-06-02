require "rails_helper"

RSpec.describe "Sendoff MCP endpoint", type: :request do
  let(:api_key) { "test-mcp-key-abc123" }
  let(:path) { "/sendoff/mcp" }

  around do |example|
    prev = ENV["SENDOFF_MCP_API_KEY"]
    ENV["SENDOFF_MCP_API_KEY"] = api_key
    example.run
    ENV["SENDOFF_MCP_API_KEY"] = prev
  end

  # JSON-RPC helpers ---------------------------------------------------------

  def rpc(method, params = {}, id: 1)
    { jsonrpc: "2.0", id: id, method: method, params: params }
  end

  def post_rpc(body, key: api_key)
    headers = { "CONTENT_TYPE" => "application/json" }
    headers["X-API-KEY"] = key unless key.nil?
    post path, params: body.to_json, headers: headers
  end

  # Extracts the JSON the tool returned inside the tools/call result envelope.
  def tool_payload(response)
    body = JSON.parse(response.body)
    text = body.dig("result", "content", 0, "text")
    JSON.parse(text)
  end

  # Auth ---------------------------------------------------------------------

  describe "authentication" do
    it "returns 401 without an API key" do
      post_rpc(rpc("tools/list"), key: nil)
      expect(response).to have_http_status(:unauthorized)
    end

    it "returns 401 with a wrong API key" do
      post_rpc(rpc("tools/list"), key: "wrong-key")
      expect(response).to have_http_status(:unauthorized)
    end

    it "returns 401 for all requests when SENDOFF_MCP_API_KEY is blank (fail closed)" do
      ENV["SENDOFF_MCP_API_KEY"] = ""
      post_rpc(rpc("tools/list"), key: api_key)
      expect(response).to have_http_status(:unauthorized)
    end

    it "accepts a request with the correct API key" do
      post_rpc(rpc("tools/list"))
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      tool_names = body.dig("result", "tools").map { |t| t["name"] }
      expect(tool_names).to include("search_leads", "queue_draft", "add_note", "move_to_stage")
    end
  end

  # Read tools ---------------------------------------------------------------

  describe "search_leads (read tool)" do
    it "returns matching leads" do
      company = create(:company, name: "Northwind", domain: "northwind.test")
      lead = create(:lead, company: company, email: "dana@northwind.test", full_name: "Dana North")

      post_rpc(rpc("tools/call", { name: "search_leads", arguments: { q: "northwind" } }))

      expect(response).to have_http_status(:ok)
      payload = tool_payload(response)
      expect(payload["ok"]).to be(true)
      emails = payload["leads"].map { |l| l["email"] }
      expect(emails).to include("dana@northwind.test")
      expect(payload["leads"].first["company_name"]).to eq("Northwind")
    end
  end

  describe "pipeline_summary (read tool)" do
    it "returns counts per stage" do
      create(:pipeline_entry, :new_stage)
      post_rpc(rpc("tools/call", { name: "pipeline_summary", arguments: {} }))

      payload = tool_payload(response)
      expect(payload["ok"]).to be(true)
      expect(payload["pipeline"]).to have_key("new")
      expect(payload.dig("pipeline", "new", "count")).to be >= 1
    end
  end

  # Write tools --------------------------------------------------------------

  describe "add_note (write tool)" do
    it "creates a note and an AuditLog with actor mcp" do
      lead = create(:lead)

      expect {
        post_rpc(rpc("tools/call", { name: "add_note", arguments: {
          content: "Spoke with them at the conference.",
          title: "Conf chat",
          lead_id: lead.id
        } }))
      }.to change { Sendoff::Note.count }.by(1)
        .and change { Sendoff::AuditLog.where(actor: "mcp", action: "mcp_add_note").count }.by(1)

      payload = tool_payload(response)
      expect(payload["ok"]).to be(true)

      note = Sendoff::Note.order(:created_at).last
      expect(note.notable).to eq(lead)
      expect(note.body_md).to eq("Spoke with them at the conference.")
      expect(note.author).to eq("mcp")
    end
  end

  describe "move_to_stage (write tool)" do
    it "moves the entry and writes an AuditLog" do
      entry = create(:pipeline_entry, :review)

      expect {
        post_rpc(rpc("tools/call", { name: "move_to_stage", arguments: {
          entry_id: entry.id, stage: "contacted"
        } }))
      }.to change { Sendoff::AuditLog.where(actor: "mcp", action: "mcp_move_to_stage").count }.by(1)

      payload = tool_payload(response)
      expect(payload["ok"]).to be(true)
      expect(payload["to_stage"]).to eq("contacted")
      expect(entry.reload.stage).to eq("contacted")
    end

    it "rejects an invalid stage" do
      entry = create(:pipeline_entry, :review)
      post_rpc(rpc("tools/call", { name: "move_to_stage", arguments: {
        entry_id: entry.id, stage: "bogus"
      } }))

      payload = tool_payload(response)
      expect(payload["ok"]).to be(false)
      expect(payload["error"]).to match(/Invalid stage/)
    end
  end

  describe "add_voice_rule (write tool)" do
    it "creates a voice rule scoped correctly" do
      expect {
        post_rpc(rpc("tools/call", { name: "add_voice_rule", arguments: {
          scope: "cold_prospect", rule: "Open with a question."
        } }))
      }.to change { Sendoff::VoiceRule.count }.by(1)
        .and change { Sendoff::AuditLog.where(action: "mcp_add_voice_rule").count }.by(1)

      payload = tool_payload(response)
      expect(payload["ok"]).to be(true)
      expect(Sendoff::VoiceRule.last.created_by).to eq("mcp")
    end
  end

  describe "skip_lead (write tool)" do
    it "hides the lead and discards pending drafts" do
      lead = create(:lead)
      draft = create(:draft, :pending, lead: lead)

      post_rpc(rpc("tools/call", { name: "skip_lead", arguments: {
        lead_id: lead.email, reason: "wrong fit"
      } }))

      payload = tool_payload(response)
      expect(payload["ok"]).to be(true)
      expect(lead.reload.hidden?).to be(true)
      expect(draft.reload.status).to eq("discarded")
      expect(Sendoff::AuditLog.where(action: "mcp_skip_lead").count).to eq(1)
    end
  end

  # Write tools backed by Drafts services owned by a parallel agent. We stub
  # those constants so this spec is self-contained.
  describe "send_draft (write tool, Drafts::Sender stubbed)" do
    it "calls Drafts::Sender and writes an AuditLog" do
      draft = create(:draft, :pending)
      sender = class_double("Sendoff::Drafts::Sender")
      stub_const("Sendoff::Drafts::Sender", sender)
      allow(sender).to receive(:call).with(draft)

      expect {
        post_rpc(rpc("tools/call", { name: "send_draft", arguments: { draft_id: draft.id } }))
      }.to change { Sendoff::AuditLog.where(action: "mcp_send_draft").count }.by(1)

      expect(sender).to have_received(:call).with(having_attributes(id: draft.id))
      payload = tool_payload(response)
      expect(payload["ok"]).to be(true)
      expect(payload["status"]).to eq("queued")
    end
  end

  describe "refine_draft (write tool, Drafts::Refiner stubbed)" do
    it "calls Drafts::Refiner and optionally adds a voice rule" do
      draft = create(:draft, :pending, subject: "Hi", body_html: "<p>old</p>")
      refiner = class_double("Sendoff::Drafts::Refiner")
      stub_const("Sendoff::Drafts::Refiner", refiner)
      allow(refiner).to receive(:call).and_return({ subject: "Hi", body_html: "<p>new shorter body</p>" })

      expect {
        post_rpc(rpc("tools/call", { name: "refine_draft", arguments: {
          draft_id: draft.id, feedback: "Make it shorter", apply_to_all: true
        } }))
      }.to change { Sendoff::VoiceRule.where(scope: "all").count }.by(1)
        .and change { Sendoff::AuditLog.where(action: "mcp_refine_draft").count }.by(1)

      expect(refiner).to have_received(:call)
      payload = tool_payload(response)
      expect(payload["ok"]).to be(true)
      expect(payload["voice_rule_added"]).to be(true)
    end
  end

  # Resources ----------------------------------------------------------------

  describe "resources/read sdr://pipeline" do
    it "returns stage counts" do
      create(:pipeline_entry, :new_stage)
      post_rpc(rpc("resources/read", { uri: "sdr://pipeline" }))

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      text = body.dig("result", "contents", 0, "text")
      data = JSON.parse(text)
      expect(data["pipeline"]).to have_key("new")
    end
  end

  describe "resources/read sdr://lead/{id}" do
    it "returns lead detail" do
      lead = create(:lead, email: "lookup@example.com")
      post_rpc(rpc("resources/read", { uri: "sdr://lead/#{lead.id}" }))

      body = JSON.parse(response.body)
      text = body.dig("result", "contents", 0, "text")
      data = JSON.parse(text)
      expect(data.dig("lead", "email")).to eq("lookup@example.com")
    end
  end

  # Prompts ------------------------------------------------------------------

  describe "prompts/get quick_lead_summary" do
    it "returns a summary prompt for a known lead" do
      lead = create(:lead, email: "summary@example.com")
      post_rpc(rpc("prompts/get", { name: "quick_lead_summary", arguments: { email: lead.email } }))

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      text = body.dig("result", "messages", 0, "content", "text")
      expect(text).to include("summary@example.com")
    end
  end
end
