# frozen_string_literal: true

require 'minitest'

# Turns a hanging end-to-end test into a failure that says where it hangs.
#
# Without it a stuck test (a blocked query, a lock, a child process that never exits) shows nothing in the log
# until CI cancels the whole job after its timeout. With it, a test that runs for more than E2E_TEST_TIMEOUT seconds
# (default 120; the slowest real test takes a few seconds) prints the test, every thread's backtrace and what the
# registered diagnostics report (the PostgreSQL suite adds the server's sessions and ungranted locks), then exits
# with status 1.
module HangWatchdog
  LIMIT = Integer(ENV.fetch('E2E_TEST_TIMEOUT', '120'))

  @mutex = Mutex.new
  @running = nil
  @diagnostics = []
  @thread = nil

  class << self
    # block: returns a String (or lines) describing the database's state; it runs when a test hangs
    def diagnose(&block)
      @mutex.synchronize { @diagnostics << block }
    end

    def started(test)
      watch
      @mutex.synchronize { @running = [test, clock] }
    end

    def finished
      @mutex.synchronize { @running = nil }
    end

    private

    def clock = ::Process.clock_gettime(::Process::CLOCK_MONOTONIC)

    def watch
      @thread ||= ::Thread.new do
        ::Thread.current.report_on_exception = false
        loop do
          sleep 1
          test, since = @mutex.synchronize { @running }
          report(test, clock - since) if test && clock - since > LIMIT
        end
      end
    end

    def report(test, seconds)
      out = ["", "HANG: #{test} has been running for #{seconds.round}s (limit #{LIMIT}s, E2E_TEST_TIMEOUT)"]
      ::Thread.list.each do |thread|
        out << "#{thread.inspect} (#{thread == ::Thread.main ? 'main' : 'other'})"
        out.concat((thread.backtrace || []).first(40).map { |line| "  #{line}" })
      end
      diagnostics.each do |block|
        out << block.call
      rescue ::StandardError, ::Timeout::Error => e
        out << "diagnostics failed: #{e.class}: #{e.message}"
      end
      warn out.join("\n")
      $stderr.flush
      exit!(1)
    end

    def diagnostics = @mutex.synchronize { @diagnostics.dup }
  end

  # Minitest::Test calls these around every test.
  def before_setup
    HangWatchdog.started("#{self.class}##{name}")
    super
  end

  def after_teardown
    super
  ensure
    HangWatchdog.finished
  end
end

Minitest::Test.include(HangWatchdog)
