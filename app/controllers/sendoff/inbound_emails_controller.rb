require "mail"

module Sendoff
  # Provider-agnostic inbound email webhook.
  #
  # A mail provider (Cloudflare Email Worker, SendGrid Inbound Parse, Mailgun
  # route, …) POSTs a copy of an outbound BCC or an inbound reply here. We parse
  # it and hand a normalized Hash to Sendoff::InboundEmail::Ingest, which records
  # a Sendoff::EmailEvent matched to the lead/company/thread.
  #
  # Auth (fail closed): a shared secret in ENV["SENDOFF_INBOUND_SECRET"] is
  # compared with ActiveSupport::SecurityUtils.secure_compare against the
  # X-Sendoff-Token header (or HTTP Basic password, for providers that only do
  # Basic). Blank env var, or a missing/wrong token, → 401.
  #
  # This is a machine webhook: CSRF is skipped and no human actor is required.
  class InboundEmailsController < ApplicationController
    skip_forgery_protection
    skip_before_action :set_actor, raise: false
    before_action :authenticate_inbound_request!

    def create
      Current.actor = "inbound"

      raw = raw_message
      parsed = raw.present? ? parse_mime(raw) : parse_fields

      return head(:unprocessable_entity) if parsed.nil?

      Sendoff::InboundEmail::Ingest.call(parsed)
      head :no_content
    ensure
      Current.reset
    end

    private

    # ---- Auth ----------------------------------------------------------------

    def authenticate_inbound_request!
      expected = ENV["SENDOFF_INBOUND_SECRET"].to_s.strip
      return render_unauthorized if expected.blank?

      provided = presented_token
      return render_unauthorized if provided.blank?
      return render_unauthorized unless ActiveSupport::SecurityUtils.secure_compare(provided, expected)

      true
    end

    # Token from the X-Sendoff-Token header, or the password half of HTTP Basic.
    def presented_token
      header = request.headers["X-Sendoff-Token"].to_s.strip
      return header if header.present?

      authenticate_with_http_basic { |_user, password| password.to_s.strip } || ""
    end

    def render_unauthorized
      render plain: "Unauthorized", status: :unauthorized
    end

    # ---- Input -------------------------------------------------------------

    # Raw RFC822 MIME source, in priority order:
    #   1. the request body when Content-Type is message/rfc822
    #   2. an :email / :raw / :message param carrying the MIME source
    def raw_message
      if request.content_type.to_s.start_with?("message/rfc822")
        body = request.body.read
        request.body.rewind if request.body.respond_to?(:rewind)
        return body if body.present?
      end

      params[:email].presence || params[:raw].presence || params[:message].presence
    end

    def parse_mime(raw)
      mail = Mail.new(raw)

      {
        message_id: mail.message_id ? "<#{mail.message_id}>" : nil,
        from: mail.from&.first,
        to: Array(mail.to),
        cc: Array(mail.cc),
        bcc: Array(mail.bcc),
        subject: mail.subject,
        text: mail.text_part&.body&.decoded || (mail.multipart? ? nil : mail.body&.decoded),
        html: mail.html_part&.body&.decoded,
        in_reply_to: header_value(mail, "In-Reply-To"),
        references: header_value(mail, "References"),
        date: mail.date&.to_time
      }
    rescue StandardError => e
      Rails.logger.warn("[Sendoff::InboundEmailsController] MIME parse failed: #{e.class}: #{e.message}")
      nil
    end

    # Pre-parsed providers (SendGrid Inbound Parse, Mailgun, a Cloudflare
    # Worker) post discrete fields. Accept them directly.
    def parse_fields
      return nil if params[:from].blank? && params[:text].blank? && params[:html].blank?

      {
        message_id: normalize_message_id(params[:message_id]),
        from: params[:from],
        to: params[:to],
        cc: params[:cc],
        bcc: params[:bcc],
        subject: params[:subject],
        text: params[:text],
        html: params[:html],
        in_reply_to: params[:in_reply_to],
        references: params[:references],
        date: params[:date]
      }
    end

    def header_value(mail, name)
      mail.header[name]&.value
    end

    # Ensure a bare provider message id is wrapped in the canonical <...> form.
    def normalize_message_id(value)
      id = value.to_s.strip
      return nil if id.blank?
      return id if id.start_with?("<")

      "<#{id}>"
    end
  end
end
