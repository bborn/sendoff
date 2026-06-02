module Sendoff
  module Gmail
    # Aggregates prior Gmail context for a lead (or domain) across all
    # EmailAccounts, fanning out concurrently with a per-account timeout.
    #
    # Clients are obtained via Sendoff.config.gmail_client_for(account) so the
    # whole layer is fake-able in tests with zero network.
    class History
      CACHE_TTL    = 60.seconds
      TIMEOUT_SECS = 5

      def self.for_lead(lead, accounts: EmailAccount.all)
        Rails.cache.fetch("sendoff_gmail_history:#{lead.id}", expires_in: CACHE_TTL) do
          fetch_from_accounts(lead.email, Array(accounts))
        end
      end

      def self.for_domain(domain, accounts: EmailAccount.all)
        Rails.cache.fetch("sendoff_gmail_domain_history:#{domain}", expires_in: CACHE_TTL) do
          fetch_domain_from_accounts(domain, Array(accounts))
        end
      end

      def self.fetch_from_accounts(email_address, accounts)
        results   = []
        timed_out = []
        mutex     = Mutex.new

        threads = accounts.map do |account|
          Thread.new do
            begin
              msgs = Timeout.timeout(TIMEOUT_SECS) do
                Sendoff.config.gmail_client_for(account)
                         .fetch_messages_for(email_address: email_address, limit: 20)
              end
              mutex.synchronize { results.concat(msgs) }
            rescue Timeout::Error
              Rails.logger.warn "[Sendoff::Gmail::History] Timeout fetching for #{account.email}"
              mutex.synchronize { timed_out << account.display_name }
            rescue => e
              Rails.logger.error "[Sendoff::Gmail::History] Error for #{account.email}: #{e.message}"
            end
          end
        end

        threads.each(&:join)

        messages = results.sort_by { |m| m[:sent_at] || Time.at(0) }.reverse.first(20)
        { messages: messages, timed_out: timed_out }
      end

      def self.fetch_domain_from_accounts(domain, accounts)
        results   = []
        timed_out = []
        mutex     = Mutex.new

        threads = accounts.map do |account|
          Thread.new do
            begin
              msgs = Timeout.timeout(TIMEOUT_SECS) do
                Sendoff.config.gmail_client_for(account)
                         .fetch_messages_for_domain(domain: domain, limit: 10)
              end
              mutex.synchronize { results.concat(msgs) }
            rescue Timeout::Error
              Rails.logger.warn "[Sendoff::Gmail::History] Timeout fetching domain=#{domain} for #{account.email}"
              mutex.synchronize { timed_out << account.display_name }
            rescue => e
              Rails.logger.error "[Sendoff::Gmail::History] Error for domain=#{domain} account=#{account.email}: #{e.message}"
            end
          end
        end

        threads.each(&:join)

        messages = results.sort_by { |m| m[:sent_at] || Time.at(0) }.reverse.first(10)
        { messages: messages, timed_out: timed_out }
      end

      private_class_method :fetch_from_accounts, :fetch_domain_from_accounts
    end
  end
end
