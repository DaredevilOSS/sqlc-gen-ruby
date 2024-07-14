using Plugin;
using RubyCodegen;
using System;
using System.Collections.Generic;
using System.Linq;

namespace SqlcGenRuby.Drivers;

public abstract class DbDriver
{
    protected static IEnumerable<RequireGem> GetCommonGems()
    {
        return [new RequireGem("connection_pool")];
    }

    public abstract IEnumerable<RequireGem> GetRequiredGems();

    public abstract MethodDeclaration GetInitMethod();

    protected abstract IEnumerable<ColumnMappingConfig> GetColumnMapping();

    public string GetColumnType(Column column)
    {
        var dbType = column.Type.Name.ToLower(); // from SQLC - char(5), char(10), int4, int8, float8, blob, etc.
        foreach (var columnMapping in GetColumnMapping())
        {
            var rubyType = columnMapping.isPrefixBased ? GetByPrefix(columnMapping) : GetByValue(columnMapping);
            if (rubyType is not null)
                return rubyType;
        }
        throw new NotSupportedException($"Unsupported column type: {column.Type.Name}");

        string? GetByValue(ColumnMappingConfig columnMapping)
        {
            return columnMapping.dbTypes.Contains(dbType) ? columnMapping.rubyType : null;
        }

        string? GetByPrefix(ColumnMappingConfig columnMapping)
        {
            return columnMapping.dbTypes.Any(d => d.StartsWith(dbType)) ? columnMapping.rubyType : null;
        }
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
}