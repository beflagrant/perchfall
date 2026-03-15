# frozen_string_literal: true

require "spec_helper"

RSpec.describe Perchfall::ConcurrencyLimiter do
  describe "#acquire" do
    context "within the limit" do
      it "yields and returns the block's value" do
        limiter = described_class.new(limit: 2)
        result  = limiter.acquire { 42 }
        expect(result).to eq(42)
      end

      it "allows concurrent acquires up to the limit" do
        limiter  = described_class.new(limit: 3)
        results  = []
        threads  = 3.times.map do
          Thread.new { results << limiter.acquire { :ok } }
        end
        threads.each(&:join)
        expect(results).to all(eq(:ok))
      end
    end

    context "at the limit" do
      it 'raises ConcurrencyLimitError immediately when limit is 0 and timeout is 0' do
        limiter = described_class.new(limit: 0, timeout_ms: 0)
        expect { limiter.acquire { } }
          .to raise_error(Perchfall::Errors::ConcurrencyLimitError)
      end

      it "blocks a second caller until the first finishes" do
        limiter   = described_class.new(limit: 1)
        order     = []
        barrier   = Mutex.new
        condvar   = ConditionVariable.new
        first_holding = false

        t1 = Thread.new do
          limiter.acquire do
            barrier.synchronize { first_holding = true; condvar.broadcast }
            sleep 0.02
            order << :first
          end
        end

        # Wait until t1 is inside acquire, then launch t2
        barrier.synchronize { condvar.wait(barrier) until first_holding }

        t2 = Thread.new { limiter.acquire { order << :second } }

        t1.join
        t2.join

        expect(order).to eq(%i[first second])
      end

      it "raises ConcurrencyLimitError when timeout is exceeded" do
        limiter  = described_class.new(limit: 1, timeout_ms: 50)
        blocker  = Thread.new { limiter.acquire { sleep 0.2 } }
        sleep 0.01 # let blocker acquire the slot

        expect { limiter.acquire { } }
          .to raise_error(Perchfall::Errors::ConcurrencyLimitError, /timeout/)

        blocker.join
      end
    end

    context "slot release" do
      it "releases the slot even when the block raises" do
        limiter = described_class.new(limit: 1)
        expect { limiter.acquire { raise "boom" } }.to raise_error("boom")
        # If the slot was not released this would deadlock / timeout
        expect { limiter.acquire { :ok } }.not_to raise_error
      end
    end
  end

  describe "#available_slots" do
    it "reports limit when nothing is running" do
      limiter = described_class.new(limit: 3)
      expect(limiter.available_slots).to eq(3)
    end

    it "decrements while a block is held" do
      limiter  = described_class.new(limit: 2)
      inside = false

      t = Thread.new do
        limiter.acquire do
          inside = true
          sleep 0.1
        end
      end

      sleep 0.01 until inside
      expect(limiter.available_slots).to eq(1)
      t.join
    end
  end
end
