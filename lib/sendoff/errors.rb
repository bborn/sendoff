module Sendoff
  # Base for all engine errors.
  class Error < StandardError; end

  # The LLM client failed to return a usable completion.
  class LLMError < Error; end

  # The drafter produced a URL that isn't on the persona's allowlist.
  class DisallowedUrlError < Error; end

  # An adapter method that subclasses must implement was called on the base class.
  class NotImplementedError < Error; end
end
