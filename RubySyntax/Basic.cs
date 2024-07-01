using SqlcGenRuby;

namespace RubyCodegen;

public class RequireGem(string gem)
{
    public string Build()
    {
        return $"require '{gem}'";
    }

    public string Name()
    {
        return gem;
    }
}

public class ModuleDeclaration(string name, IEnumerable<IComposable> members) : IComposable, IRbsType
{
    public string BuildCode()
    {
        var moduleBody = members
            .Select(m => m.BuildCode())
            .JoinByNewLine(2)
            .Indent();
        return $"module {name}\n{moduleBody}\nend";
    }

    public string BuildType()
    {
        var moduleBody = members
            .Where(m => m is IRbsType)
            .Select(m => ((IRbsType)m).BuildType())
            .JoinByNewLine(2)
            .Indent();
        return $"module {name}\n{moduleBody}\nend";
    }
}

public class ClassDeclaration(string name, IEnumerable<IComposable> members) : IComposable, IRbsType
{
    public string BuildCode()
    {
        var classBody = members
            .Select(m => m.BuildCode())
            .JoinByNewLine(2)
            .Indent();
        return $"class {name}\n{classBody}\nend";
    }

    public string BuildType()
    {
        var moduleBody = members
            .Where(m => m is IRbsType)
            .Select(m => ((IRbsType)m).BuildType())
            .JoinByNewLine()
            .Indent();
        return $"class {name}\n{moduleBody}\nend";
    }
}

public class MethodDeclaration(string name, string? argInterface, string? args, string? returnInterface,
    IEnumerable<IComposable> statements) : IComposable, IRbsType
{
    public string BuildCode()
    {
        var methodParams = args is null ? string.Empty : $"({args})";
        var methodBody = statements
            .Select(c => c.BuildCode())
            .JoinByNewLine()
            .Indent();
        return $"def {name}{methodParams}\n{methodBody}\nend";
    }

    public string BuildType()
    {
        var methodParams = args is null ? string.Empty : $"({argInterface}) ";
        var returnType = returnInterface ?? "void";
        var propertiesDef = statements
            .Where(s => s is PropertyDeclaration)
            .Select(s => ((IRbsType)s).BuildType())
            .JoinByNewLine();
        return $"{propertiesDef}\ndef {name}: {methodParams}-> {returnType}";
    }
}

public class PropertyDeclaration(string name, string constType, IComposable value) : IComposableRbsType
{
    public string BuildCode()
    {
        return $"{name.FirstCharToUpper()} = {value.BuildCode()}".TrimTrailingWhitespacesPerLine();
    }

    public string BuildType()
    {
        return $"{name}: {constType}";
    }
}

public class SimpleStatement(string assignment, IComposable expression) : IComposable
{
    public string BuildCode()
    {
        return $"{assignment} = {expression.BuildCode()}".TrimTrailingWhitespacesPerLine();
    }
}

public class SimpleExpression(string expression) : IComposable
{
    public string BuildCode()
    {
        return expression;
    }
}

public class DataDefine(string name, Dictionary<string, string> nameToType) : IComposableRbsType
{
    public string BuildCode()
    {
        var attributes = nameToType
            .Select(kv => $":{kv.Key}")
            .ToList()
            .JoinByCommaAndFormat();
        return $"class {name} < Data.define({attributes})\nend";
    }

    public string BuildType()
    {
        var attributes = nameToType
            .Select(column => $"attr_reader {column.Key}: {column.Value}")
            .ToList()
            .JoinByNewLine()
            .Indent();
        var initializeArgs = nameToType
            .Select(kv => $"{kv.Value} {kv.Key}")
            .ToList()
            .JoinByCommaAndFormat()
            .Indent();
        var initializeDef = $"def initialize: ({initializeArgs}) -> void".Indent();
        return $"class {name}\n{attributes}\n{initializeDef}\nend";
    }
}

public class NewStruct(string name, Dictionary<string, string> nameToType) : IComposableRbsType
{
    public string BuildCode()
    {
        var initializeDef = nameToType.Select(kv => kv.Key).ToList().JoinByCommaAndFormat();
        return $"class {name} < Struct.new({initializeDef})\nend";
    }

    public string BuildType()
    {
        var attributes = nameToType
            .Select(kv => $"attr_accessor {kv.Key}: {kv.Value}")
            .ToList()
            .JoinByNewLine()
            .Indent();
        var initializeArgs = nameToType
            .Select(kv => $"{kv.Value} {kv.Key}")
            .ToList()
            .JoinByCommaAndFormat()
            .Indent();
        var initializeDef = $"def self.new: ({initializeArgs}) -> {name}".Indent();
        return $"class {name} < ::Struct\n{attributes}\n{initializeDef}\nend";
    }
}