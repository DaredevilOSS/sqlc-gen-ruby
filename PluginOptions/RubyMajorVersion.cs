using System.Collections.Generic;
using System.Linq;

namespace SqlcGenCsharp;

public enum RubyMajorVersion
{
    Ruby1,
    Ruby2,
    Ruby3
}

public static class DotnetFrameworkExtensions
{
    private static readonly Dictionary<RubyMajorVersion, string> EnumToString = new()
    {
        { RubyMajorVersion.Ruby1, "ruby1.0" },
        { RubyMajorVersion.Ruby2, "ruby2.7" },
        { RubyMajorVersion.Ruby3, "ruby3.3" }
    };

    public static string ToName(this RubyMajorVersion me)
    {
        return EnumToString[me];
    }

    public static RubyMajorVersion ParseName(string dotnetFramework)
    {
        return EnumToString
            .ToDictionary(x => x.Value, x => x.Key)
            [dotnetFramework];
    }

    public static bool LatestRubySupported(this RubyMajorVersion me)
    {
        return me == RubyMajorVersion.Ruby3;
    }
}