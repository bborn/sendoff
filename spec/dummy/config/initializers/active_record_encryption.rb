# Deterministic, non-secret encryption keys for the dummy app so that
# `encrypts :oauth_refresh_token` on Sendoff::EmailAccount works in tests
# and local dev. A real host configures these via credentials / ENV.
Rails.application.config.active_record.encryption.primary_key =
  ENV.fetch("AR_ENCRYPTION_PRIMARY_KEY", "dummy_primary_key_for_tests_0000000000")
Rails.application.config.active_record.encryption.deterministic_key =
  ENV.fetch("AR_ENCRYPTION_DETERMINISTIC_KEY", "dummy_deterministic_key_tests_000000")
Rails.application.config.active_record.encryption.key_derivation_salt =
  ENV.fetch("AR_ENCRYPTION_KEY_DERIVATION_SALT", "dummy_key_derivation_salt_for_tests0")
