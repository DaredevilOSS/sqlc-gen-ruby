using SqlcGenCsharp;

namespace RubyCodegen;

public class RequireGem(string gem)
{
    public string Build()
    {
        return $"require '{gem}'";
    }

    public string GetName()
    {
        return gem;
    }
}

public class ModuleDeclaration(string name, IEnumerable<IComposable> members) : IComposable
{
    public string Build()
    {
        var moduleBody = members
            .Select(m => m.Build())
            .JoinByNewLine(2)
            .Indent();
        return $"module {name}\n{moduleBody}\nend";
    }
}

public class ClassDeclaration(string name, IEnumerable<IComposable> members) : IComposable
{
    public string Build()
    {
        var classBody = members
            .Select(m => m.Build())
            .JoinByNewLine(2)
            .Indent();
        return $"class {name}\n{classBody}\nend";
    }
}

public class MethodDeclaration(string name, string? args, IEnumerable<IComposable> statements) : IComposable
{
    public string Build()
    {
        var methodParams = args is null ? string.Empty : $"({args})";
        var methodBody = statements
            .Select(c => c.Build())
            .JoinByNewLine()
            .Indent();
        return $"def {name}{methodParams}\n{methodBody}\nend";
    }
}

public class SimpleStatement(string assignment, IComposable expression) : IComposable
{
    public string Build()
    {
        return $"{assignment} = {expression.Build()}".TrimTrailingWhitespacesPerLine();
    }
}

public class SimpleExpression(string expression) : IComposable
{
    public string Build()
    {
        return expression;
    }
}