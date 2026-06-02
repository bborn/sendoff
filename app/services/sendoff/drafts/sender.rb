module Sendoff
  module Drafts
    # Raised when a send would exceed the configured daily/hourly cap or the
    # per-recipient cooldown window.
    class RateLimitExceeded < StandardError; end

    # Sends a Draft via Gmail, advancing the pipeline entry and recording the
    # outbound EmailEvent + AuditLog. Two modes:
    #
    #   immediate: true  → send synchronously (used by DeliverJob and tests)
    #   immediate: false → enqueue DeliverJob with a 60s hold, return :queued
    #
    # All host-specific behavior is routed through Sendoff.config:
    #   - caps/cooldown -> config.send_daily_cap / send_hourly_cap / recipient_cooldown_days
    #   - gmail         -> config.gmail_client_for(account)
    #   - default cc/bcc -> config.persona.default_cc / default_bcc
    class Sender
      def self.call(draft, immediate: false, **kwargs)
        new(draft).call(immediate: immediate, **kwargs)
      end

      def initialize(draft)
        @draft = draft
        raise ArgumentError, "draft must have email_account" unless @draft.email_account
      end

      def call(immediate: false, subject: nil, body_html: nil, to_addr: nil, cc_addr: nil, bcc_addr: nil)
        effective_subject = subject.presence   || @draft.subject
        effective_body    = body_html.presence || @draft.body_html
        effective_to      = to_addr.presence   || @draft.to_addr
        effective_cc      = cc_addr.presence   || @draft.cc_addr.presence || default_cc
        effective_bcc     = bcc_addr.presence  || @draft.bcc_addr.presence || default_bcc

        check_rate_limits!(effective_to)

        if immediate
          send_now!(effective_subject, effective_body, effective_to, effective_cc, effective_bcc)
        else
          enqueue_with_hold!(effective_subject, effective_body, effective_to, effective_cc, effective_bcc)
          :queued
        end
      end

      private

      def daily_cap     = Sendoff.config.send_daily_cap
      def hourly_cap    = Sendoff.config.send_hourly_cap
      def cooldown_days = Sendoff.config.recipient_cooldown_days

      # Persona defaults applied only when the draft itself carries no explicit
      # cc/bcc. A single string or an array are both tolerated.
      def default_cc  = Array(Sendoff.config.persona.default_cc).first
      def default_bcc = Array(Sendoff.config.persona.default_bcc).first

      def check_rate_limits!(to_addr)
        outbound = EmailEvent.where(direction: "outbound")

        daily_count  = outbound.where("sent_at > ?", 24.hours.ago).count
        hourly_count = outbound.where("sent_at > ?", 1.hour.ago).count

        Rails.logger.info("[Sendoff::Drafts::Sender] daily=#{daily_count}/#{daily_cap} hourly=#{hourly_count}/#{hourly_cap} to=#{to_addr}")

        if daily_count >= daily_cap
          raise RateLimitExceeded, "Rate limit hit: #{daily_count} sends already in last 24h (cap #{daily_cap})"
        end

        if hourly_count >= hourly_cap
          raise RateLimitExceeded, "Rate limit hit: #{hourly_count} sends already in last hour (cap #{hourly_cap})"
        end

        addr_lower = to_addr.to_s.downcase
        recent_to_recipient = outbound
          .where("sent_at > ?", cooldown_days.days.ago)
          .where("to_addrs @> ARRAY[?]::varchar[]", addr_lower)
          .exists?

        if recent_to_recipient
          raise RateLimitExceeded, "Rate limit hit: already sent to #{to_addr} within last #{cooldown_days} days"
        end
      end

      def enqueue_with_hold!(subject, body, to, cc, bcc)
        @draft.update!(
          status: :sending,
          to_addr: to,
          cc_addr: cc,
          bcc_addr: bcc,
          subject: subject,
          body_html: body
        )

        job = Sendoff::Drafts::DeliverJob.set(wait: 60.seconds).perform_later(@draft.id)
        @draft.update_column(:send_job_id, job.provider_job_id.to_s) if job.provider_job_id
      end

      def send_now!(subject, body, to, cc, bcc)
        gmail_message_id = gmail_client.send_message(
          to: to,
          subject: subject,
          body_html: body,
          cc: cc,
          bcc: bcc,
          thread_id: @draft.gmail_thread_id
        )

        @draft.class.transaction do
          @draft.update!(
            status: :sent,
            sent_at: Time.current,
            subject: subject,
            body_html: body
          )

          advance_pipeline_to_contacted!

          EmailEvent.create!(
            lead:             @draft.lead,
            company:          @draft.lead.company,
            direction:        :outbound,
            email_account:    @draft.email_account,
            gmail_message_id: gmail_message_id,
            gmail_thread_id:  @draft.gmail_thread_id,
            from_addr:        @draft.email_account.email,
            to_addrs:         [ to.to_s.downcase ],
            cc_addrs:         cc.present?  ? [ cc ]  : [],
            bcc_addrs:        bcc.present? ? [ bcc ] : [],
            subject:          subject,
            body_html:        body,
            sent_at:          Time.current
          )

          AuditLog.record!(
            action:        "sent",
            subject:       @draft,
            recipient:     to,
            email_account: @draft.email_account,
            detail:        "subject=#{subject.inspect}"
          )
        end

        gmail_message_id
      end

      # Advance the pipeline entry to :contacted, honoring PROTECTED_STAGES so a
      # replied/dud entry is never regressed by a send.
      def advance_pipeline_to_contacted!
        entry = @draft.pipeline_entry
        return unless entry
        return if Sendoff::PipelineEntry::PROTECTED_STAGES.include?(entry.stage)

        entry.update!(stage: :contacted)
      end

      def gmail_client
        @gmail_client ||= Sendoff.config.gmail_client_for(@draft.email_account)
      end
    end
  end
end
