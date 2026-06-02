require "rails_helper"

module Sendoff
  RSpec.describe Current do
    after { Current.reset }

    it "holds an actor attribute" do
      Current.actor = "agent:internal"
      expect(Current.actor).to eq("agent:internal")
    end

    describe "#actor_or_system" do
      it "returns the actor when set" do
        Current.actor = "dana@example.com"
        expect(Current.actor_or_system).to eq("dana@example.com")
      end

      it "falls back to system when blank" do
        expect(Current.actor_or_system).to eq("system")
        Current.actor = ""
        expect(Current.actor_or_system).to eq("system")
      end
    end
  end
end
