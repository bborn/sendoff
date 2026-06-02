module Sendoff
  class VoiceRulesController < ApplicationController
    # Human-readable labels for the model's real scope values
    # (Sendoff::VoiceRule::SCOPES). Used for filter chips and the scope select.
    SCOPE_LABELS = {
      "all"               => "All variants",
      "cold_prospect"     => "Cold prospect",
      "customer_success"  => "Customer success",
      "reengage_cold"     => "Re-engage cold",
      "reengage_customer" => "Re-engage customer"
    }.freeze

    SCOPE_BADGE = {
      "all"               => "badge-gray",
      "cold_prospect"     => "badge-blue",
      "customer_success"  => "badge-green",
      "reengage_cold"     => "badge-amber",
      "reengage_customer" => "badge-purple"
    }.freeze

    helper_method :scope_label, :scope_badge_class

    def index
      @scope_labels = SCOPE_LABELS
      @scope_filter = params[:scope].to_s.presence

      rules = VoiceRule.all
      rules = rules.for_scope(@scope_filter) if VoiceRule::SCOPES.include?(@scope_filter)
      @rules = rules.order(active: :desc, created_at: :desc)
    end

    def create
      @rule = VoiceRule.new(rule_params)
      @rule.created_by = Sendoff::Current.actor_or_system

      if @rule.save
        AuditLog.record!(
          action: "voice_rule_created",
          subject: @rule,
          detail: "#{@rule.scope}: #{@rule.rule}"
        )
        respond_to do |format|
          format.turbo_stream
          format.html { redirect_to voice_rules_path, notice: "Voice rule added." }
        end
      else
        respond_to do |format|
          format.turbo_stream { render :create, status: :unprocessable_entity }
          format.html { redirect_to voice_rules_path, alert: @rule.errors.full_messages.to_sentence }
        end
      end
    end

    def update
      @rule = VoiceRule.find(params[:id])

      if @rule.update(rule_params)
        AuditLog.record!(
          action: "voice_rule_updated",
          subject: @rule,
          detail: "#{@rule.scope}: #{@rule.rule}"
        )
        respond_to do |format|
          format.turbo_stream
          format.html { redirect_to voice_rules_path, notice: "Voice rule updated." }
        end
      else
        respond_to do |format|
          format.turbo_stream { render :update, status: :unprocessable_entity }
          format.html { redirect_to voice_rules_path, alert: @rule.errors.full_messages.to_sentence }
        end
      end
    end

    def toggle
      @rule = VoiceRule.find(params[:id])
      @rule.update!(active: !@rule.active)

      AuditLog.record!(
        action: @rule.active? ? "voice_rule_enabled" : "voice_rule_disabled",
        subject: @rule,
        detail: @rule.rule
      )

      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to voice_rules_path }
      end
    end

    def destroy
      @rule = VoiceRule.find(params[:id])
      @rule.destroy

      AuditLog.record!(
        action: "voice_rule_deleted",
        subject: @rule,
        detail: "#{@rule.scope}: #{@rule.rule}"
      )

      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to voice_rules_path, notice: "Voice rule deleted." }
      end
    end

    private

    def rule_params
      params.require(:voice_rule).permit(:scope, :rule)
    end

    def scope_label(scope)
      SCOPE_LABELS[scope.to_s] || scope.to_s.humanize
    end

    def scope_badge_class(scope)
      SCOPE_BADGE[scope.to_s] || "badge-gray"
    end
  end
end
