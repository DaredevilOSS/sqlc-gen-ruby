using SqlcGenCsharp;

namespace RubyCodegen;

public class WithResource(string resourceFrom, string resourceName, IEnumerable<IComposable> statements) : IComposable
{
    public string Build()
    {
        var withResourceBody = statements
            .Select(s => s.Build())
            .JoinByNewLine()
            .TrimTrailingWhitespacesPerLine()
            .Indent();
        var withResource = $"{resourceFrom}.with do |{resourceName}|\n{withResourceBody}\nend";
        return withResource;
    }
}

public class IfCondition(string condition, IList<IComposable> thenStatements,
    IList<IComposable>? elseStatements = null) : IComposable
{
    public string Build()
    {
        var thenBody = thenStatements
            .Select(s => s.Build())
            .JoinByNewLine()
            .TrimTrailingWhitespacesPerLine()
            .Indent();
        if (elseStatements is null || elseStatements.Count == 0)
            return $"if {condition}\n{thenBody}\nend";
        var elseBody = elseStatements
            .Select(s => s.Build())
            .JoinByNewLine()
            .TrimTrailingWhitespacesPerLine()
            .Indent();
        return $"if {condition}\n{thenStatements}\nelse\n{elseBody}\nend";
    }
}

public class UnlessCondition(string condition, IList<IComposable> thenStatements) : IComposable
{
    public string Build()
    {
        var thenBody = thenStatements
            .Select(s => s.Build())
            .JoinByNewLine()
            .TrimTrailingWhitespacesPerLine()
            .Indent();
        return $"unless {condition}\n{thenBody}\nend";
    }
}

public class NewObject(string objectType, IEnumerable<SimpleExpression> initExpressions,
    IEnumerable<IComposable>? bodyStatements = null) : IComposable
{
    public string Build()
    {
        var initParams = initExpressions
            .Select(e => e.Build())
            .JoinByCommaAndNewLine()
            .Indent();
        var baseCommand = $"{objectType}.new(\n{initParams}\n)";
        if (bodyStatements is null)
            return baseCommand;

        var body = "{\n" + bodyStatements
            .Select(s => s.Build())
            .JoinByNewLine()
            .TrimTrailingWhitespacesPerLine()
            .Indent() + "\n}";
        return $"{baseCommand} {body}";
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