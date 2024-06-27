using System;
using System.Text.RegularExpressions;
using Enum = System.Enum;

namespace SqlcGenCsharp;

public enum RubyVersion
{
    V31,
    V32,
    V33
}

public static partial class RubyVersionExtensions
{
    public static RubyVersion ParseName(string versionPattern)
    {
        var semanticVersionRegex = SemanticVersionRegex();
        var match = semanticVersionRegex.Match(versionPattern);
        if (!match.Success)
            throw new ArgumentException($"version {versionPattern} can't be parsed to a ruby version");

        var major = short.Parse(match.Groups[1].Value);
        if (major != 3)
            throw new ArgumentException($"Ruby versions older than Ruby3 are not supported");

        short? minor = null;
        if (match.Groups[2].Success)
            minor = short.Parse(match.Groups[2].Value);
        if ((minor is < 1 or > 3))
            throw new ArgumentException($"Ruby versions newer than Ruby3.3 do not exist");

        // short? patch = null; patch version is currently not interesting
        // if (match.Groups[3].Success)
        //    patch = short.Parse(match.Groups[3].Value);

        var rubyVersionStr = $"V{major}.{minor}";
        var valid = Enum.TryParse(rubyVersionStr, out RubyVersion rubyVersion);
        if (!valid)
            throw new ArgumentException($"Failed to parse {rubyVersionStr} to {nameof(RubyVersion)}");
        return rubyVersion;
    }

    public static bool LatestRubySupported(this RubyVersion me)
    {
        return me is RubyVersion.V32 or RubyVersion.V33;
    }

    [GeneratedRegex(@"^(0|[1-9][0-9]*)(?:\.(0|[1-9][0-9]*))?(?:\.(0|[1-9][0-9]*))?$")]
    private static partial Regex SemanticVersionRegex();
}