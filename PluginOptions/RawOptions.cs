using System.Text.Json.Serialization;

namespace SqlcGenRuby;

internal class RawOptions
{
    [JsonPropertyName("driver")]
    public required string DriverName { get; init; }

    [JsonPropertyName("generateGemfile")]
    public bool GenerateGemfile { get; init; } // not generating Gemfile files by default

    [JsonPropertyName("rubyVersion")]
    public string RubyVersion { get; init; } = "3.3";
}