require "rails_helper"
require "mail"

module Sendoff
  RSpec.describe "Inbound emails", type: :request do
    include Engine.routes.url_helpers

    let(:secret) { "s3cr3t-token" }

    def raw_mime(from:, to:, subject: "Hello", body: "Body text", message_id: "<req-1@ourco.com>")
      mail = Mail.new do
        from    from
        to      to
        subject subject
        body    body
        date    Time.utc(2026, 6, 1, 12)
      end
      mail.message_id = message_id
      mail.to_s
    end

    around do |example|
      original = ENV["SENDOFF_INBOUND_SECRET"]
      example.run
      if original.nil?
        ENV.delete("SENDOFF_INBOUND_SECRET")
      else
        ENV["SENDOFF_INBOUND_SECRET"] = original
      end
    end

    describe "POST /inbound_emails (auth)" do
      it "returns 401 when SENDOFF_INBOUND_SECRET is unset" do
        ENV.delete("SENDOFF_INBOUND_SECRET")

        post inbound_emails_path,
             params: raw_mime(from: "rep@ourco.com", to: "buyer@acme.com"),
             headers: { "CONTENT_TYPE" => "message/rfc822", "X-Sendoff-Token" => "anything" }

        expect(response).to have_http_status(:unauthorized)
      end

      it "returns 401 with no token" do
        ENV["SENDOFF_INBOUND_SECRET"] = secret

        post inbound_emails_path,
             params: raw_mime(from: "rep@ourco.com", to: "buyer@acme.com"),
             headers: { "CONTENT_TYPE" => "message/rfc822" }

        expect(response).to have_http_status(:unauthorized)
      end

      it "returns 401 with a wrong token" do
        ENV["SENDOFF_INBOUND_SECRET"] = secret

        post inbound_emails_path,
             params: raw_mime(from: "rep@ourco.com", to: "buyer@acme.com"),
             headers: { "CONTENT_TYPE" => "message/rfc822", "X-Sendoff-Token" => "wrong" }

        expect(response).to have_http_status(:unauthorized)
      end
    end

    describe "POST /inbound_emails (success)" do
      before { ENV["SENDOFF_INBOUND_SECRET"] = secret }

      it "returns 204 with the correct token and a raw MIME body, and creates the event" do
        create(:email_account, email: "rep@ourco.com")
        lead = create(:lead, email: "buyer@acme.com")

        expect {
          post inbound_emails_path,
               params: raw_mime(from: "rep@ourco.com", to: "buyer@acme.com",
                                message_id: "<live-1@ourco.com>"),
               headers: { "CONTENT_TYPE" => "message/rfc822", "X-Sendoff-Token" => secret }
        }.to change(EmailEvent, :count).by(1)

        expect(response).to have_http_status(:no_content)

        event = EmailEvent.find_by(gmail_message_id: "<live-1@ourco.com>")
        expect(event.direction).to eq("outbound")
        expect(event.lead).to eq(lead)
      end

      it "accepts the secret as an HTTP Basic password" do
        create(:email_account, email: "rep@ourco.com")
        create(:lead, email: "buyer@acme.com")

        post inbound_emails_path,
             params: raw_mime(from: "rep@ourco.com", to: "buyer@acme.com",
                              message_id: "<basic-1@ourco.com>"),
             headers: {
               "CONTENT_TYPE" => "message/rfc822",
               "HTTP_AUTHORIZATION" => ActionController::HttpAuthentication::Basic.encode_credentials("provider", secret)
             }

        expect(response).to have_http_status(:no_content)
        expect(EmailEvent.find_by(gmail_message_id: "<basic-1@ourco.com>")).to be_present
      end

      it "accepts a pre-parsed field payload (provider that posts JSON/form fields)" do
        create(:email_account, email: "rep@ourco.com")
        create(:lead, email: "buyer@acme.com")

        post inbound_emails_path,
             params: {
               from: "buyer@acme.com",
               to: "rep@ourco.com",
               subject: "Re: pitch",
               text: "Sounds good",
               message_id: "fields-1@acme.com"
             },
             headers: { "X-Sendoff-Token" => secret }

        expect(response).to have_http_status(:no_content)
        event = EmailEvent.find_by(gmail_message_id: "<fields-1@acme.com>")
        expect(event.direction).to eq("inbound")
        expect(event.subject).to eq("Re: pitch")
      end
    end
  end
end
