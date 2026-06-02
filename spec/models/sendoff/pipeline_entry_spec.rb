require "rails_helper"

module Sendoff
  RSpec.describe PipelineEntry, type: :model do
    around do |example|
      old = ActiveJob::Base.queue_adapter
      ActiveJob::Base.queue_adapter = :test
      example.run
      ActiveJob::Base.queue_adapter = old
    end

    it "has a valid factory" do
      expect(build(:pipeline_entry)).to be_valid
    end

    describe "stage enum" do
      it "keeps the six stages in order" do
        expect(PipelineEntry.stages.keys).to eq(%w[new drafting review contacted replied dud])
      end
    end

    describe "PROTECTED_STAGES" do
      it "is replied and dud" do
        expect(PipelineEntry::PROTECTED_STAGES).to match_array(%w[replied dud])
      end

      it "prevents regression out of replied" do
        pe = create(:pipeline_entry, :replied)
        pe.stage = "new"
        expect(pe).not_to be_valid
        expect(pe.errors[:stage].join).to match(/protected/)
      end

      it "prevents regression out of dud" do
        pe = create(:pipeline_entry, :dud)
        pe.stage = "drafting"
        expect(pe).not_to be_valid
      end

      it "allows forward movement into protected stages" do
        pe = create(:pipeline_entry, :contacted)
        pe.stage = "replied"
        expect(pe).to be_valid
      end
    end

    describe "drafting callback" do
      it "enqueues Sendoff::DraftJob when stage becomes drafting" do
        stub_const("Sendoff::DraftJob", Class.new(ActiveJob::Base))
        pe = create(:pipeline_entry, :new_stage)
        expect {
          pe.update!(stage: "drafting")
        }.to have_enqueued_job(Sendoff::DraftJob)
      end

      it "does not enqueue when DraftJob is undefined" do
        hide_const("Sendoff::DraftJob") if Sendoff.const_defined?(:DraftJob, false)
        pe = create(:pipeline_entry, :new_stage)
        expect { pe.update!(stage: "drafting") }.not_to raise_error
      end

      it "honors skip_draft_callbacks" do
        stub_const("Sendoff::DraftJob", Class.new(ActiveJob::Base))
        pe = create(:pipeline_entry, :new_stage)
        expect {
          PipelineEntry.skip_draft_callbacks { pe.update!(stage: "drafting") }
        }.not_to have_enqueued_job(Sendoff::DraftJob)
      end

      it "resets the skip flag after the block" do
        PipelineEntry.skip_draft_callbacks { }
        expect(PipelineEntry.skip_draft_callbacks?).to be(false)
      end
    end

    describe "#warm_signal?" do
      it "is true when any signal value is truthy" do
        expect(build(:pipeline_entry, signals: { "warm_account" => true }).warm_signal?).to be(true)
      end

      it "is false for empty signals" do
        expect(build(:pipeline_entry, signals: {}).warm_signal?).to be(false)
      end

      it "is false when all signals are false" do
        expect(build(:pipeline_entry, signals: { "warm_account" => false }).warm_signal?).to be(false)
      end
    end
  end
end
