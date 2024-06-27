using System.Text.Json.Serialization;

namespace SqlcGenCsharp;

internal class RawOptions
{
    [JsonPropertyName("driver")]
    public required string DriverName { get; init; }

    [JsonPropertyName("generateGemfile")]
    public bool GenerateGemfile { get; init; } // not generating Gemfile files by default

    [JsonPropertyName("rubyVersionPattern")]
    public string RubyVersionPattern { get; init; } = "3.3";
}