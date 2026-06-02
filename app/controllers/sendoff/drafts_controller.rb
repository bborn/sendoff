module Sendoff
  class DraftsController < ApplicationController
    before_action :set_draft, only: %i[edit send_now schedule refine discard]

    # Drafts awaiting human action: pending review or scheduled-for-later.
    REVIEWABLE_STATUSES = %w[pending scheduled].freeze

    def index
      @drafts = Draft.where(status: REVIEWABLE_STATUSES)
                     .order(created_at: :desc)
                     .includes(:email_account, lead: :company)
    end

    # Rendered into the Turbo Frame on the index, which surfaces as a <dialog>.
    def edit
      render partial: "modal", locals: { draft: @draft }
    end

    def send_now
      account = swap_account_if_requested!

      Sendoff::Drafts::Sender.call(
        @draft,
        immediate: true,
        to_addr:   params[:to_addr].presence,
        cc_addr:   collected_cc.presence,
        bcc_addr:  params[:bcc_addr].presence,
        subject:   params[:subject].presence,
        body_html: params[:body_html].presence
      )

      Sendoff::AuditLog.record!(
        action:        "draft_sent",
        subject:       @draft,
        recipient:     @draft.to_addr,
        email_account: account
      )

      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: [
            turbo_stream.remove(dom_id(@draft, :card)),
            close_modal_stream,
            toast_stream("Sent to #{@draft.to_addr}.")
          ]
        end
        format.html { redirect_to drafts_path, notice: "Sent to #{@draft.to_addr}." }
      end
    rescue Sendoff::Drafts::RateLimitExceeded => e
      respond_to do |format|
        format.turbo_stream do
          render status: :unprocessable_entity, turbo_stream:
            turbo_stream.replace("draft-modal-frame",
              partial: "modal", locals: { draft: @draft, rate_limit_error: e.message })
        end
        format.html { redirect_to drafts_path, alert: e.message }
      end
    end

    def schedule
      account      = swap_account_if_requested!
      scheduled_at = parse_scheduled_at(params[:schedule_option], params[:custom_dt])

      unless scheduled_at && scheduled_at.future?
        return respond_to do |format|
          format.turbo_stream do
            render status: :unprocessable_entity, turbo_stream:
              turbo_stream.replace("draft-modal-frame",
                partial: "modal", locals: { draft: @draft, schedule_error: "Pick a valid future time." })
          end
          format.html { redirect_to drafts_path, alert: "Pick a valid future time." }
        end
      end

      # Persist any edits made in the modal before scheduling.
      @draft.assign_attributes(
        to_addr:   params[:to_addr].presence   || @draft.to_addr,
        cc_addr:   collected_cc.presence,
        bcc_addr:  params[:bcc_addr],
        subject:   params[:subject].presence   || @draft.subject,
        body_html: params[:body_html].presence || @draft.body_html
      )
      @draft.status       = :scheduled
      @draft.scheduled_at = scheduled_at
      @draft.save!

      Sendoff::Drafts::DeliverJob.set(wait_until: scheduled_at).perform_later(@draft.id)

      Sendoff::AuditLog.record!(
        action:        "draft_scheduled",
        subject:       @draft,
        recipient:     @draft.to_addr,
        email_account: account,
        detail:        "scheduled_at=#{scheduled_at.iso8601} option=#{params[:schedule_option]}"
      )

      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: [
            turbo_stream.replace(dom_id(@draft, :card), partial: "card", locals: { draft: @draft }),
            close_modal_stream,
            toast_stream("Scheduled for #{format_scheduled(scheduled_at)}.")
          ]
        end
        format.html { redirect_to drafts_path, notice: "Scheduled for #{format_scheduled(scheduled_at)}." }
      end
    end

    def refine
      feedback = params[:feedback].to_s.strip
      if feedback.blank?
        return respond_to do |format|
          format.turbo_stream do
            render status: :unprocessable_entity, turbo_stream:
              turbo_stream.replace("draft-modal-frame",
                partial: "modal", locals: { draft: @draft, refine_error: "Add some feedback first." })
          end
          format.html { redirect_to drafts_path, alert: "Add some feedback first." }
        end
      end

      new_account = requested_account
      new_account = nil if new_account && new_account == @draft.email_account

      # The Refiner persists a VoiceRule itself when the feedback reads like a
      # rule. The "save as voice rule" checkbox phrases the feedback as an
      # imperative so the Refiner's rule detection fires.
      effective_feedback =
        if ActiveModel::Type::Boolean.new.cast(params[:save_voice_rule]) && !rule_like?(feedback)
          "Always #{feedback}"
        else
          feedback
        end

      Sendoff::Drafts::Refiner.call(@draft, feedback: effective_feedback, email_account: new_account)
      @draft.reload

      Sendoff::AuditLog.record!(
        action:        "draft_refined",
        subject:       @draft,
        recipient:     @draft.to_addr,
        email_account: @draft.email_account,
        detail:        "feedback=#{feedback.first(200).inspect}"
      )

      respond_to do |format|
        format.turbo_stream do
          render turbo_stream:
            turbo_stream.replace("draft-modal-frame", partial: "modal", locals: { draft: @draft })
        end
        format.html { redirect_to drafts_path }
      end
    end

    def discard
      delete_gmail_draft(@draft)
      @draft.update!(status: :discarded)

      Sendoff::AuditLog.record!(
        action:        "draft_discarded",
        subject:       @draft,
        recipient:     @draft.to_addr,
        email_account: @draft.email_account
      )

      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: [
            turbo_stream.remove(dom_id(@draft, :card)),
            close_modal_stream,
            toast_stream("Draft discarded.")
          ]
        end
        format.html { redirect_to drafts_path, notice: "Draft discarded." }
      end
    end

    private

    def set_draft
      @draft = Draft.where(status: REVIEWABLE_STATUSES).find(params[:id])
    rescue ActiveRecord::RecordNotFound
      respond_to do |format|
        format.turbo_stream { render turbo_stream: close_modal_stream }
        format.html { redirect_to drafts_path, alert: "Draft not found." }
      end
    end

    # If the human picked a different "From" mailbox, swap the underlying account
    # (deletes old Gmail preview draft, rebuilds it in the target mailbox) before
    # the send/schedule fires. Returns the account the draft now sends from.
    def swap_account_if_requested!
      target = requested_account
      if target && target != @draft.email_account
        Sendoff::Drafts::Refiner.switch_account!(@draft, target)
        @draft.reload
      end
      @draft.email_account
    end

    def requested_account
      return nil if params[:from].blank?
      EmailAccount.for_outreach.find_by("LOWER(email) = ?", params[:from].to_s.downcase)
    end

    # Merge CC mailbox checkboxes with the free-text extra-CC field.
    def collected_cc
      ccs  = Array(params[:cc_accounts]).map(&:to_s)
      ccs += params[:cc_addr_extra].to_s.split(",")
      ccs.map(&:strip).reject(&:blank?).uniq.join(", ")
    end

    def rule_like?(feedback)
      Sendoff::Drafts::Refiner::RULE_PREFIXES.any? do |prefix|
        feedback.downcase.strip.start_with?(prefix)
      end
    end

    def delete_gmail_draft(draft)
      return if draft.gmail_draft_id.blank? || draft.email_account.nil?
      Sendoff.config.gmail_client_for(draft.email_account).delete_draft(draft.gmail_draft_id)
    rescue => e
      Rails.logger.warn("[Sendoff::DraftsController#discard] gmail delete failed: #{e.class}: #{e.message}")
    end

    def parse_scheduled_at(option, custom_dt)
      now   = Time.current
      today = now.to_date

      case option
      when "tomorrow_morning"   then (today + 1).in_time_zone.change(hour: 9)
      when "tomorrow_afternoon" then (today + 1).in_time_zone.change(hour: 14)
      when "custom"
        return nil if custom_dt.blank?
        Time.zone.parse(custom_dt.to_s)
      end
    rescue ArgumentError, TypeError
      nil
    end

    def format_scheduled(at)
      at.in_time_zone.strftime("%-l:%M %p, %a %b %-d")
    end

    def close_modal_stream
      turbo_stream.update("draft-modal-frame", "")
    end

    def toast_stream(message)
      turbo_stream.append("toast-container", partial: "toast", locals: { message: message })
    end

    def dom_id(draft, prefix)
      "draft-#{prefix}-#{draft.id}"
    end
    helper_method :dom_id
  end
end
