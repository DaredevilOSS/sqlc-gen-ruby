using System.Text.Json.Serialization;

namespace SqlcGenCsharp;

internal class RawOptions
{
    [JsonPropertyName("driver")] public required string DriverName { get; init; }

    [JsonPropertyName("generateGemfile")]
    public bool GenerateGemfile { get; init; } // not generating Gemfile files by default

    [JsonPropertyName("rubyVersionPattern")]
    public string RubyVersionPattern { get; init; } = RubyVersion.V33.ToString();

    [JsonPropertyName("filePerQuery")] public bool FilePerQuery { get; init; } // generating single file by default
}