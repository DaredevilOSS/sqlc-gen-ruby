# frozen_string_literal: true

module SqlcGenRuby
  # Port of PluginOptions/RubyVersion.cs. The comparison deliberately mirrors the C# record's
  # CompareTo, including its handling of omitted minor / patch parts (e.g. "3" compares equal to any
  # "3.x", while "3.3.5" compares greater than "3.3", so it is rejected by the max-version check).
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
        raise ArgumentError, "Provided version #{version} exceeds min version #{MIN_SUPPORTED}"
      end
      if version > MAX_SUPPORTED
        raise ArgumentError, "Provided version #{version} exceeds max version #{MAX_SUPPORTED}"
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

      cmp = major <=> other.major
      return cmp unless cmp.zero?
      return cmp if minor.nil?

      cmp = compare_nullable(minor, other.minor)
      return cmp unless cmp.zero?
      return cmp if patch.nil?

      compare_nullable(patch, other.patch)
    end

    # Records compare by value in C# (`==`), unlike CompareTo which treats missing parts as "equal".
    def ==(other)
      other.is_a?(RubyVersion) && [major, minor, patch] == [other.major, other.minor, other.patch]
    end
    alias eql? ==

    def hash = [major, minor, patch].hash

    # Ruby 3.2 introduced Data.define; older versions have to fall back to Struct.
    def immutable_data_supported?
      self >= IMMUTABLE_DATA_MIN
    end

    def to_s
      [major, minor, patch].compact.join('.')
    end

    # int.CompareTo(int?): a missing value sorts before any number.
    def compare_nullable(value, other)
      other.nil? ? 1 : value <=> other
    end
    private :compare_nullable

    MIN_SUPPORTED = new(3, 1).freeze
    MAX_SUPPORTED = new(3, 4).freeze
    IMMUTABLE_DATA_MIN = new(3, 2).freeze
  end
end
