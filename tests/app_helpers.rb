# frozen_string_literal: true

# Helpers for the tests that use the generated code the way applications do.
module AppHelpers
  # The smallest pool an application hands in: one connection it also uses itself (a raw driver connection shared
  # with another library, or a connection opened before forking).
  class SingleConnection
    def initialize(connection)
      @connection = connection
    end

    def with
      yield @connection
    end
  end

  # Runs the block in a forked child (Puma / Sidekiq / Resque workers) and returns its value, or the class and
  # message of what it raised.
  def in_forked_child
    reader, writer = ::IO.pipe
    parent = ::Process.pid
    pid = fork_child(parent) do
      reader.close
      result = begin
        yield
      rescue ::Exception => e
        "#{e.class}: #{e.message}"
      end
      writer.write(::Marshal.dump(result))
      writer.close
      exit!(0)
    end
    writer.close
    result = ::Marshal.load(reader.read)
    ::Process.wait(pid)
    result
  ensure
    reader&.close
  end

  # A fork hook that raises in the child (connection_pool's after_fork) must not let the child run the rest of the suite.
  def fork_child(parent, &)
    fork(&)
  rescue ::Exception
    exit!(1) unless ::Process.pid == parent
    raise
  end

  def skip_without_fork
    skip 'Process.fork is not available on this platform' unless ::Process.respond_to?(:fork)
  end
end
