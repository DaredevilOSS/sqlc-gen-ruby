using SqlcGenCsharp;

namespace RubyCodegen;

public class WithResource(string resourceFrom, string resourceName, IEnumerable<IComposable> statements) : IComposable
{
    public string Build()
    {
        var withResourceBody = statements.Select(s => s.Build())
            .JoinByNewLine()
            .TrimTrailingWhitespacesPerLine()
            .Indent();
        var withResource = $"{resourceFrom}.with do |{resourceName}|\n{withResourceBody}\nend";
        return withResource;
    }
}

public class NewObject(string objectType, IEnumerable<SimpleExpression> initExpressions,
    IComposable? bodyExpression = null) : IComposable
{
    public string Build()
    {
        var optionalBody = bodyExpression is null
            ? string.Empty
            : $$""" { {{bodyExpression.Build()}} }""";
        var initParams = initExpressions
            .Select(e => e.Build())
            .JoinByCommaAndNewLine()
            .Indent();
        var newObject = $"{objectType}.new(\n{initParams}\n){optionalBody}";
        return newObject;
    }
}

public class ForeachLoop(string collectionVar, string controlVar, IEnumerable<IComposable> statements) : IComposable
{
    public string Build()
    {
        var foreachBody = statements
            .Select(s => s.Build())
            .JoinByNewLine();
        var foreachLoop = $"{collectionVar}.each do |{controlVar}|\n{foreachBody}\nend";
        return foreachLoop;
    }
}

public class ListAppend(string listVar, NewObject newObject) : IComposable
{
    public string Build()
    {
        return $"{listVar} << {newObject.Build()}";
    }
}