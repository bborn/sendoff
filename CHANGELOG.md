# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Initial extraction of `Sendoff` from an internal SDR tool into a generic,
  MIT-licensed mountable Rails engine. Domain-specific behavior moves out of the core
  and into pluggable seams:
  - **Persona** value object — sender identity, product name/description, voice guide,
    outreach principles, allowed URL patterns, default CC/BCC, and per-segment prompt
    hints.
  - **Adapters** — `LeadSource` (warm-lead intake), `AccountLookup` (lead → account
    mapping), and `BrandMentionSource` (optional social proof), each with a network-free
    null default and normalized value objects (`LeadData`, `AccountInfo`).
  - **Pluggable LLM client** — any object responding to `#complete(prompt) -> String`.
    Ships with `LLM::ClaudeCliClient` (headless `claude` CLI) and `LLM::FakeClient`
    (deterministic, network-free, for tests and demos).
  - **`Sendoff.configure`** central configuration with send-safety tunables
    (daily/hourly caps, recipient cooldown, fresh-touch window) and a
    hallucination-critic toggle.
- Pipeline state machine, drafter + voice/hallucination critics, send-safety guards,
  Gmail integration, and an MCP server (ported as generic engine internals).

[Unreleased]: https://github.com/bborn/sendoff/commits/main
