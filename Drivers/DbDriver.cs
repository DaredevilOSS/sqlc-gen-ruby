using Plugin;
using RubyCodegen;
using System;
using System.Collections.Generic;

namespace SqlcGenRuby.Drivers;

public abstract class DbDriver
{
    protected static IEnumerable<RequireGem> GetCommonGems()
    {
        return [new RequireGem("connection_pool")];
    }

    public abstract IEnumerable<RequireGem> GetRequiredGems();

    public abstract MethodDeclaration GetInitMethod();

    protected abstract List<(string, HashSet<string>)> GetColumnMapping();

    public string GetColumnType(Column column)
    {
        var columnType = column.Type.Name.ToLower();
        foreach (var (csharpType, dbTypes) in GetColumnMapping())
        {
            if (dbTypes.Contains(columnType))
                return csharpType;
        }
        throw new NotSupportedException($"Unsupported column type: {column.Type.Name}");
    }

    public abstract PropertyDeclaration QueryTextConstantDeclare(Query query);

    public abstract IComposable PrepareStmt(string funcName, string queryTextConstant);

    public abstract SimpleExpression ExecuteStmt(string funcName, SimpleStatement? queryParams);

    public abstract MethodDeclaration OneDeclare(string name, string sqlTextConstant, string argInterface,
        string returnInterface, IList<Parameter> parameters, IList<Column> columns);

    public abstract MethodDeclaration ManyDeclare(string funcName, string sqlTextConstant, string argInterface,
        string returnInterface, IList<Parameter> parameters, IList<Column> columns);

    public abstract MethodDeclaration ExecDeclare(string funcName, string text, string argInterface,
        IList<Parameter> parameters);

    public abstract MethodDeclaration ExecLastIdDeclare(string funcName, string queryTextConstant, string argInterface,
        IList<Parameter> parameters);
}