require "rails_helper"

module Sendoff
  RSpec.describe "Drafts", type: :request do
    include Engine.routes.url_helpers

    let(:account) { create(:email_account, :outreach) }
    let(:lead)    { create(:lead) }

    def make_draft(*traits, **attrs)
      create(:draft, *traits, lead: lead, email_account: account, **attrs)
    end

    describe "GET /drafts" do
      it "renders 200 and lists pending drafts" do
        draft = make_draft(subject: "Hello from us", to_addr: "person@acme.test")

        get drafts_path

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("person@acme.test")
        expect(response.body).to include("Hello from us")
        # Sender-mailbox badge is derived from the account, not hardcoded.
        expect(response.body).to include(account.display_name)
      end

      it "includes scheduled drafts and excludes sent/discarded" do
        pending_d   = make_draft(subject: "Pending one")
        scheduled_d = make_draft(:scheduled, subject: "Scheduled one")
        make_draft(:sent, subject: "Already sent")
        make_draft(:discarded, subject: "Thrown away")

        get drafts_path

        expect(response.body).to include("Pending one")
        expect(response.body).to include("Scheduled one")
        expect(response.body).not_to include("Already sent")
        expect(response.body).not_to include("Thrown away")
      end

      it "shows an empty state when nothing is pending" do
        get drafts_path
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("All caught up")
      end
    end

    describe "GET /drafts/:id/edit" do
      it "renders the review modal dialog" do
        draft = make_draft(subject: "Review me")

        get edit_draft_path(draft)

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("<dialog")
        expect(response.body).to include("Review me")
        expect(response.body).to include("Send now")
        expect(response.body).to include("Refine")
        expect(response.body).to include("Schedule")
      end

      it "defaults BCC to the persona default_bcc, never a hardcoded address" do
        Sendoff.config.persona = Sendoff::Persona.new(
          product_name: "Acme", sender_name: "Dana", sender_email: "dana@acme.test",
          default_bcc: ["log@acme.test"]
        )
        draft = make_draft

        get edit_draft_path(draft)

        expect(response.body).to include("log@acme.test")
      end

      it "surfaces flagged claims as a warning" do
        draft = make_draft(:hallucination_flagged)

        get edit_draft_path(draft)

        expect(response.body).to include("Unverified claims")
        expect(response.body).to include("made up fact")
      end
    end

    describe "POST /drafts/:id/send_now" do
      it "invokes the Sender and removes the card" do
        draft = make_draft

        expect(Sendoff::Drafts::Sender).to receive(:call)
          .with(draft_matching(draft.id), hash_including(immediate: true))
          .and_return("msg-1")

        post send_now_draft_path(draft), params: { to_addr: draft.to_addr, subject: draft.subject, body_html: draft.body_html },
             headers: { "Accept" => "text/vnd.turbo-stream.html" }

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("draft-card-#{draft.id}")
        expect(response.body).to include("turbo-stream")
        expect(response.media_type).to eq("text/vnd.turbo-stream.html")
      end

      it "writes an audit log on send" do
        draft = make_draft
        allow(Sendoff::Drafts::Sender).to receive(:call).and_return("msg-1")

        expect {
          post send_now_draft_path(draft), params: { subject: draft.subject, body_html: draft.body_html },
               headers: { "Accept" => "text/vnd.turbo-stream.html" }
        }.to change { Sendoff::AuditLog.where(action: "draft_sent").count }.by(1)
      end

      it "re-renders the modal with the error when rate limited" do
        draft = make_draft
        allow(Sendoff::Drafts::Sender).to receive(:call)
          .and_raise(Sendoff::Drafts::RateLimitExceeded, "too many sends")

        post send_now_draft_path(draft), params: { subject: draft.subject, body_html: draft.body_html },
             headers: { "Accept" => "text/vnd.turbo-stream.html" }

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.body).to include("too many sends")
      end
    end

    describe "POST /drafts/:id/schedule" do
      it "sets scheduled_at and status and enqueues delivery" do
        draft = make_draft

        expect {
          post schedule_draft_path(draft),
               params: { schedule_option: "tomorrow_morning", subject: draft.subject, body_html: draft.body_html },
               headers: { "Accept" => "text/vnd.turbo-stream.html" }
        }.to have_enqueued_job(Sendoff::Drafts::DeliverJob)

        draft.reload
        expect(draft.status).to eq("scheduled")
        expect(draft.scheduled_at).to be_present
        expect(draft.scheduled_at).to be > Time.current
      end

      it "rejects an invalid/past time" do
        draft = make_draft

        post schedule_draft_path(draft),
             params: { schedule_option: "custom", custom_dt: "" },
             headers: { "Accept" => "text/vnd.turbo-stream.html" }

        expect(response).to have_http_status(:unprocessable_entity)
        expect(draft.reload.status).to eq("pending")
      end
    end

    describe "POST /drafts/:id/refine" do
      it "invokes the Refiner and re-renders the modal" do
        draft = make_draft

        expect(Sendoff::Drafts::Refiner).to receive(:call)
          .with(draft_matching(draft.id), hash_including(feedback: "make it shorter"))
          .and_return(subject: draft.subject, body_html: draft.body_html)

        post refine_draft_path(draft), params: { feedback: "make it shorter" },
             headers: { "Accept" => "text/vnd.turbo-stream.html" }

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("draft-modal-frame")
      end

      it "passes a rule-phrased feedback through when save_voice_rule is checked" do
        draft = make_draft

        expect(Sendoff::Drafts::Refiner).to receive(:call) do |_d, feedback:, **|
          expect(feedback).to start_with("Always")
          { subject: draft.subject, body_html: draft.body_html }
        end

        post refine_draft_path(draft),
             params: { feedback: "include the pricing link", save_voice_rule: "1" },
             headers: { "Accept" => "text/vnd.turbo-stream.html" }

        expect(response).to have_http_status(:ok)
      end

      it "rejects blank feedback" do
        draft = make_draft
        expect(Sendoff::Drafts::Refiner).not_to receive(:call)

        post refine_draft_path(draft), params: { feedback: "  " },
             headers: { "Accept" => "text/vnd.turbo-stream.html" }

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    describe "POST /drafts/:id/discard" do
      it "marks the draft discarded and removes the card" do
        draft = make_draft

        post discard_draft_path(draft), headers: { "Accept" => "text/vnd.turbo-stream.html" }

        expect(response).to have_http_status(:ok)
        expect(draft.reload.status).to eq("discarded")
        expect(response.body).to include("draft-card-#{draft.id}")
      end

      it "writes an audit log on discard" do
        draft = make_draft

        expect {
          post discard_draft_path(draft), headers: { "Accept" => "text/vnd.turbo-stream.html" }
        }.to change { Sendoff::AuditLog.where(action: "draft_discarded").count }.by(1)
      end
    end

    # Matches the Sender/Refiner being called with the right draft id without
    # caring about object identity (the controller may reload).
    def draft_matching(id)
      satisfy { |d| d.is_a?(Sendoff::Draft) && d.id == id }
    end
  end
end
