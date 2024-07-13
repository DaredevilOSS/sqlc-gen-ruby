namespace SqlcGenRuby.Drivers;

public enum Variable
{
    Db,
    PreparedStatements,
    QueryParams,
    Client,
    Stmt,
    Result,
    Row,
    Entity,
    Entities
}

public static class VariablesExtensions
{
    public static string AsVar(this Variable me)
    {
        return me.ToString().SnakeCase();
    }

    public static string AsProperty(this Variable me)
    {
        return $"@{me.ToString().SnakeCase()}";
    }
}