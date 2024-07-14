using System.Collections.Generic;

namespace SqlcGenRuby.Drivers;

public readonly record struct ColumnMappingConfig(
    string rubyType,
    HashSet<string> dbTypes,
    bool isPrefixBased
);