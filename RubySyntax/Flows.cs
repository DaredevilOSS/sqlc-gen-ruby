using SqlcGenRuby;

namespace RubyCodegen;

public class WithResource(string resourceFrom, string resourceName, IList<IComposable> statements) : IComposable
{
    public string BuildCode()
    {
        var withResourceBody = statements
            .Select(s => s.BuildCode())
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
    public string BuildCode()
    {
        var thenBody = thenStatements
            .Select(s => s.BuildCode())
            .JoinByNewLine()
            .TrimTrailingWhitespacesPerLine()
            .Indent();
        if (elseStatements is null || elseStatements.Count == 0)
            return $"if {condition}\n{thenBody}\nend";
        var elseBody = elseStatements
            .Select(s => s.BuildCode())
            .JoinByNewLine()
            .TrimTrailingWhitespacesPerLine()
            .Indent();
        return $"if {condition}\n{thenStatements}\nelse\n{elseBody}\nend";
    }
}

public class UnlessCondition(string condition, IList<IComposable> thenStatements) : IComposable
{
    public string BuildCode()
    {
        var thenBody = thenStatements
            .Select(s => s.BuildCode())
            .JoinByNewLine()
            .TrimTrailingWhitespacesPerLine()
            .Indent();
        return $"unless {condition}\n{thenBody}\nend";
    }
}

public class NewObject(string objectType, IList<SimpleExpression> initExpressions,
    IList<IComposable>? bodyStatements = null) : IComposable
{
    public string BuildCode()
    {
        var initParams = initExpressions
            .Select(e => e.BuildCode())
            .ToList()
            .JoinByCommaAndFormat();
        var baseCommand = $"{objectType}.new({initParams})";
        if (bodyStatements is null)
            return baseCommand;

        var body = "{\n" + bodyStatements
            .Select(s => s.BuildCode())
            .JoinByNewLine()
            .TrimTrailingWhitespacesPerLine()
            .Indent() + "\n}";
        return $"{baseCommand} {body}";
    }
}

public class ForeachLoop(string collectionVar, string controlVar, IList<IComposable> statements) : IComposable
{
    public string BuildCode()
    {
        var foreachBody = statements
            .Select(s => s.BuildCode())
            .JoinByNewLine()
            .Indent();
        var foreachLoop = $"{collectionVar}.each do |{controlVar}|\n{foreachBody}\nend";
        return foreachLoop;
    }
}

public class ListAppend(string listVar, NewObject newObject) : IComposable
{
    public string BuildCode()
    {
        return $"{listVar} << {newObject.BuildCode()}";
    }
}