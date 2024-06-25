using Plugin;
using System;
using System.Text;
using System.Text.Json;
using Enum = System.Enum;

namespace SqlcGenCsharp;

public enum DriverName
{
    Mysql2,
    Pg
}

public class Options
{
    public Options(GenerateRequest generateRequest)
    {
        var text = Encoding.UTF8.GetString(generateRequest.PluginOptions.ToByteArray());
        var rawOptions = JsonSerializer.Deserialize<RawOptions>(text) ?? throw new InvalidOperationException();

        Enum.TryParse(rawOptions.DriverName, true, out DriverName outDriverName);
        DriverName = outDriverName;
        FilePerQuery = rawOptions.FilePerQuery;
        GenerateCsproj = rawOptions.GenerateCsproj;
        RubyMajorVersion = DotnetFrameworkExtensions.ParseName(rawOptions.TargetFramework);
    }

    public DriverName DriverName { get; }

    public RubyMajorVersion RubyMajorVersion { get; }

    public bool FilePerQuery { get; }

    public bool GenerateCsproj { get; }
}