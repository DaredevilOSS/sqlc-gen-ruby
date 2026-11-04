# frozen_string_literal: true

module SqlcGenRuby
  # The `rubyVersion` option. Every version decision compares the *oldest release it covers*: an omitted minor part
  # means the oldest supported release of that major ("3" is 3.1, "4" is 4.0) and an omitted patch part means .0, so
  # "3" is below 3.2 and below 3.3 alike. The max-version check ignores the patch part.
  class RubyVersion
    include Comparable

    SEMVER = /\A\s*(0|[1-9][0-9]*)(?:\.(0|[1-9][0-9]*))?(?:\.(0|[1-9][0-9]*))?\s*\z/.freeze
    SHORT_MAX = 32_767 # the C# implementation parses each part as a `short`

    attr_reader :major, :minor, :patch

    def initialize(major, minor = nil, patch = nil)
      @major = major
      @minor = minor
      @patch = patch
    end

    def self.parse(pattern)
      version = parse_semantic(pattern)
      if version < MIN_SUPPORTED
        raise ArgumentError, "Provided version #{version} is below the minimum supported version #{MIN_SUPPORTED}"
      end
      if new(version.major, version.minor) > MAX_SUPPORTED # any patch release of the newest minor is fine
        raise ArgumentError, "Provided version #{version} is above the maximum supported version #{MAX_SUPPORTED}"
      end

      version
    end

    def self.parse_semantic(pattern)
      match = SEMVER.match(pattern.to_s) or
        raise ArgumentError, "version #{pattern} can't be parsed to a semantic version"
      parts = match.captures.map { |c| c && short(c) }
      new(*parts)
    end

    def self.short(text)
      n = Integer(text, 10)
      raise ArgumentError, "version part #{text} is out of range" if n > SHORT_MAX

      n
    end

    def <=>(other)
      return 1 if other.nil?

      oldest_release <=> other.oldest_release
    end

    def ==(other)
      other.is_a?(RubyVersion) && [major, minor, patch] == [other.major, other.minor, other.patch]
    end
    alias eql? ==

    def hash = [major, minor, patch].hash

    # [major, minor, patch] of the oldest Ruby release this version covers.
    def oldest_release
      [major, minor || (major == MIN_SUPPORTED.major ? MIN_SUPPORTED.minor : 0), patch || 0]
    end

    # Ruby 3.2 introduced Data.define; older versions have to fall back to Struct.
    def immutable_data_supported? = self >= IMMUTABLE_DATA_MIN

    # Before Ruby 3.3 the default timeout gem (< 0.4) exits a Timeout.timeout block with throw, so generated
    # transactions cannot tell it apart from a break / throw out of their block.
    def legacy_timeout? = self < MODERN_TIMEOUT_MIN

    def to_s
      [major, minor, patch].compact.join('.')
    end

    MIN_SUPPORTED = new(3, 1).freeze
    MAX_SUPPORTED = new(4, 0).freeze
    IMMUTABLE_DATA_MIN = new(3, 2).freeze
    MODERN_TIMEOUT_MIN = new(3, 3).freeze
  end
end
