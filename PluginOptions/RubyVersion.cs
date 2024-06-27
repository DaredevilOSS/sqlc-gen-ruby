using System;
using System.Text.RegularExpressions;

namespace SqlcGenRuby;

public record RubyVersion(short Major, short? Minor, short? Patch = null) : IComparable<RubyVersion>
{
    public int CompareTo(RubyVersion? other)
    {
        if (other is null) return 1;

        var majorComparison = Major.CompareTo(other.Major);
        if (majorComparison != 0) return majorComparison;

        if (Minor == null)
            return majorComparison;

        var minorComparison = Minor.Value.CompareTo(other.Minor);
        if (minorComparison != 0) return minorComparison;

        return Patch?.CompareTo(other.Patch) ?? minorComparison;
    }

    public bool AtLeast(RubyVersion other) => CompareTo(other) >= 0;

    public bool AtMost(RubyVersion other) => CompareTo(other) <= 0;
}

public static partial class RubyVersionExtensions
{
    private static readonly RubyVersion MinSupportedVersion = new(3, 1);
    private static readonly RubyVersion MaxSupportedVersion = new(3, 3);

    public static RubyVersion ParseName(string versionPattern)
    {
        var rubyVersion = ParseSemanticVersion(versionPattern);
        if (!rubyVersion.AtLeast(MinSupportedVersion))
            throw new ArgumentException($"Provided version {rubyVersion} exceeds min version {MinSupportedVersion}");
        if (!rubyVersion.AtMost(MaxSupportedVersion))
            throw new ArgumentException($"Provided version {rubyVersion} exceeds max version {MaxSupportedVersion}");
        return rubyVersion;
    }

    private static RubyVersion ParseSemanticVersion(string versionPattern)
    {
        var semanticVersionRegex = SemanticVersionRegex();
        var match = semanticVersionRegex.Match(versionPattern);
        if (!match.Success)
            throw new ArgumentException($"version {versionPattern} can't be parsed to a semantic version");

        var major = short.Parse(match.Groups[1].Value);
        short? minor = null;
        if (match.Groups[2].Success)
            minor = short.Parse(match.Groups[2].Value);
        short? patch = null;
        if (match.Groups[3].Success)
            patch = short.Parse(match.Groups[3].Value);

        return new RubyVersion(major, minor, patch);
    }

    public static bool ImmutableDataSupported(this RubyVersion me)
    {
        return me.AtLeast(new RubyVersion(3, 2));
    }

    [GeneratedRegex(@"^(0|[1-9][0-9]*)(?:\.(0|[1-9][0-9]*))?(?:\.(0|[1-9][0-9]*))?$")]
    private static partial Regex SemanticVersionRegex();
}