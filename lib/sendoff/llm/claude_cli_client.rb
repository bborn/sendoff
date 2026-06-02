require "open3"

module Sendoff
  module LLM
    # The default LLM client: shells out to the `claude` CLI in headless mode.
    # The binary is resolved from (in order) the constructor arg, the
    # SENDOFF_CLAUDE_BIN env var, or "claude" on PATH.
    #
    # Swap this out for any object responding to #complete(prompt) -> String
    # (e.g. a RubyLLM- or anthropic-gem-backed client) via Sendoff.configure.
    class ClaudeCliClient
      def initialize(binary: nil, extra_args: [])
        @binary     = binary || ENV["SENDOFF_CLAUDE_BIN"] || "claude"
        @extra_args = extra_args
      end

      def complete(prompt)
        env = ENV.to_h.except("CLAUDECODE").merge("TERM" => "dumb")
        args = [ @binary, "-p", "--output-format", "text", *@extra_args, prompt ]
        stdout, stderr, status = Open3.capture3(env, *args)
        unless status.success?
          raise Sendoff::LLMError,
                "`#{@binary} -p` failed (exit #{status.exitstatus}): #{stderr.to_s.first(400)}"
        end
        stdout.strip
      end
    end
  end
end
