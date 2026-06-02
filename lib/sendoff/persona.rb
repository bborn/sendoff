module Sendoff
  # Everything about *who* is writing and *what* they're selling, in one value
  # object. This is what replaces the hardcoded sender, product, and voice content
  # that used to live inside the drafter and critic prompts.
  #
  #   Sendoff::Persona.new(
  #     product_name:        "Acme Analytics",
  #     product_description: "a reporting tool for agencies",
  #     sender_name:         "Dana Lee",
  #     sender_email:        "dana@acme.test",
  #     voice_guide:         File.read("config/voice_guide.md"),
  #     outreach_principles: File.read("config/outreach_principles.md"),
  #     allowed_url_patterns: [%r{\Ahttps://calendar\.acme\.test/}],
  #     default_cc:          ["founder@acme.test"]
  #   )
  class Persona
    attr_reader :product_name, :product_description, :sender_name, :sender_email,
                :voice_guide, :outreach_principles, :allowed_url_patterns,
                :default_cc, :default_bcc, :segment_prompt_hints

    def initialize(
      product_name:,
      sender_name:,
      sender_email:,
      product_description: nil,
      voice_guide: "",
      outreach_principles: "",
      allowed_url_patterns: [],
      default_cc: [],
      default_bcc: [],
      segment_prompt_hints: {}
    )
      @product_name         = product_name
      @product_description  = product_description
      @sender_name          = sender_name
      @sender_email         = sender_email
      @voice_guide          = voice_guide.to_s
      @outreach_principles  = outreach_principles.to_s
      @allowed_url_patterns = Array(allowed_url_patterns)
      @default_cc           = Array(default_cc)
      @default_bcc          = Array(default_bcc)
      @segment_prompt_hints = segment_prompt_hints || {}
    end

    # A generic, no-frills persona used as the default so the engine boots
    # without configuration. Real hosts override via Sendoff.configure.
    def self.default
      new(
        product_name:        "Your Product",
        product_description: "a product worth telling people about",
        sender_name:         "Sender",
        sender_email:        "sender@example.com"
      )
    end
  end
end
