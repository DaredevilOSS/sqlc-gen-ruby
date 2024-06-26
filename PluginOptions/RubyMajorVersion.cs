using System.Collections.Generic;
using System.Linq;

namespace SqlcGenCsharp;

public enum RubyVersion
{
    Ruby1,
    Ruby2,
    Ruby3
}

public static class DotnetFrameworkExtensions
{
    private static readonly Dictionary<RubyVersion, string> EnumToString = new()
    {
        { RubyVersion.Ruby1, "ruby1.0" },
        { RubyVersion.Ruby2, "ruby2.7" },
        { RubyVersion.Ruby3, "ruby3.3" }
    };

    public static string ToName(this RubyVersion me)
    {
        return EnumToString[me];
    }

    public static RubyVersion ParseName(string dotnetFramework)
    {
        return EnumToString
            .ToDictionary(x => x.Value, x => x.Key)
            [dotnetFramework];
    }

    public static bool LatestRubySupported(this RubyVersion me)
    {
        return me == RubyVersion.Ruby3;
    }
}