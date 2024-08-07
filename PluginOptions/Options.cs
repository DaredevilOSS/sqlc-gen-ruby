using Plugin;
using System;
using System.Text;
using System.Text.Json;
using Enum = System.Enum;

namespace SqlcGenRuby;

public enum DriverName
{
    Mysql2,
    Pg,
    Sqlite3
}

public class Options
{
    public Options(GenerateRequest generateRequest)
    {
        var text = Encoding.UTF8.GetString(generateRequest.PluginOptions.ToByteArray());
        var rawOptions = JsonSerializer.Deserialize<RawOptions>(text) ?? throw new InvalidOperationException();

        Enum.TryParse(rawOptions.DriverName, true, out DriverName outDriverName);
        DriverName = outDriverName;
        GenerateGemfile = rawOptions.GenerateGemfile;
        GenerateTypes = rawOptions.GenerateTypes;
        RubyVersion = RubyVersionExtensions.ParseName(rawOptions.RubyVersion);
    }

    public DriverName DriverName { get; }

    public RubyVersion RubyVersion { get; }

    public bool GenerateGemfile { get; }

    public bool GenerateTypes { get; }
}