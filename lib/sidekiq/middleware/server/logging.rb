module Sidekiq
  module Middleware
    module Server
      class Logging

        def call(worker, item, queue)
          Sidekiq::Logging.with_context(log_context(worker, item)) do
            begin
              start = Time.now
              logger.info { "#{Thread.current.object_id.to_s(36)} started: #{printable_item(item)}" }

              yield

              job_name = item['class'].split(':').last

              created_at_to_completion = elapsed(Time.at(item['created_at']))
              enqueued_at_to_completion = elapsed(Time.at(item['enqueued_at']))

              StatsD.measure("job.#{job_name}.response", elapsed(start))
              StatsD.measure("job.#{job_name}.created_at_to_completion", created_at_to_completion)
              StatsD.measure("job.#{job_name}.enqueued_at_to_completion", enqueued_at_to_completion)

              message  = "#{Thread.current.object_id.to_s(36)} processed: #{item['jid']} "
              message += "(job:#{elapsed(start)}ms, created_at_to_completion:#{created_at_to_completion}ms, enqueued_at_to_completion:#{enqueued_at_to_completion}ms)"

              logger.info { message }
            rescue Exception
              StatsD.increment("job.errored")

              logger.info { "#{Thread.current.object_id.to_s(36)} errored: #{item['jid']} took #{elapsed(start)}ms" }
              raise
            end
          end
        end

        private

        # If we're using a wrapper class, like ActiveJob, use the "wrapped"
        # attribute to expose the underlying thing.
        def log_context(worker, item)
          klass = item['wrapped'.freeze] || worker.class.to_s
          "#{klass} JID-#{item['jid'.freeze]}#{" BID-#{item['bid'.freeze]}" if item['bid'.freeze]}"
        end

        def printable_item(item)
          item_to_print = item.dup

          item_to_print['args'] = item_to_print['args'].map do |arg|
            unless arg.is_a?(Array) && arg.count > 5
              arg
            else
              "<Array of #{arg.count} elements>"
            end
          end

          Sidekiq.dump_json(item_to_print)
        end

        def elapsed(start)
          ((Time.now - start) * 1000).round
        end

        def logger
          Sidekiq.logger
        end
      end
    end
  end
end

