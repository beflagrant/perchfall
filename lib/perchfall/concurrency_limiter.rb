# frozen_string_literal: true

module Perchfall
  # Caps the number of Playwright browser processes that can run simultaneously.
  #
  # Uses a Mutex + ConditionVariable semaphore so threads block (up to
  # timeout_ms) rather than spinning. The slot is always released in an
  # ensure block so a raising caller cannot leak it.
  #
  # Usage:
  #   limiter = ConcurrencyLimiter.new(limit: 5, timeout_ms: 10_000)
  #   limiter.acquire { do_expensive_work }
  #
  # Raises Errors::ConcurrencyLimitError if timeout_ms elapses before a
  # slot is available.
  class ConcurrencyLimiter
    DEFAULT_TIMEOUT_MS = 30_000

    def initialize(limit:, timeout_ms: DEFAULT_TIMEOUT_MS)
      @limit      = limit
      @timeout_s  = timeout_ms / 1000.0
      @count      = 0
      @mutex      = Mutex.new
      @condvar    = ConditionVariable.new
    end

    def acquire
      acquire_slot!
      begin
        yield
      ensure
        release_slot!
      end
    end

    def available_slots
      @mutex.synchronize { @limit - @count }
    end

    private

    def acquire_slot!
      @mutex.synchronize do
        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + @timeout_s

        while @count >= @limit
          remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
          raise Errors::ConcurrencyLimitError,
                "Concurrency limit of #{@limit} reached; timeout of #{@timeout_s}s exceeded" if remaining <= 0

          @condvar.wait(@mutex, remaining)
        end

        @count += 1
      end
    end

    def release_slot!
      @mutex.synchronize do
        @count -= 1
        @condvar.signal
      end
    end
  end
end
