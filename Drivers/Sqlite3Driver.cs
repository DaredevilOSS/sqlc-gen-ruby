using Plugin;
using RubyCodegen;
using System.Collections.Generic;
using System.Linq;

namespace SqlcGenRuby.Drivers;

public class Sqlite3Driver : DbDriver
{
    private MethodGen MethodGen { get; }

    public Sqlite3Driver()
    {
        MethodGen = new MethodGen(this);
    }

    public override IEnumerable<RequireGem> GetRequiredGems()
    {
        return GetCommonGems().Append(new RequireGem("sqlite3"));
    }

    public override MethodDeclaration GetInitMethod()
    {
        return new MethodDeclaration("initialize", "untyped", "db", null,
            [
                new PropertyDeclaration(Variable.Db.AsProperty(), "untyped", new SimpleExpression("db"))
            ]
        );
    }

    protected override IEnumerable<ColumnMappingConfig> GetColumnMapping()
    {
        return
        [
            new ColumnMappingConfig("Integer", [
                "int",
                "integer",
                "tinyint",
                "smallint",
                "mediumint",
                "bigint",
                "unsignedbigint",
                "int2",
                "int8"
            ], false),
            new ColumnMappingConfig("bool", ["boolean", "bool"], false),
            new ColumnMappingConfig("Array[Integer]", ["blob"], false),
            new ColumnMappingConfig("String", [
                "character",
                "varchar",
                "varyingcharacter",
                "nchar",
                "nativecharacter",
                "nvarchar",
                "text",
                "clob"
            ], true),
            new ColumnMappingConfig("Float", [
                "real",
                "double",
                "doubleprecision",
                "float",
                "decimal",
                "numeric"
            ], true),
        ];
    }

    public override PropertyDeclaration QueryTextConstantDeclare(Query query)
    {
        return new PropertyDeclaration(
            $"{query.Name}{ClassMember.Sql}",
            "String",
            new SimpleExpression($"%q({query.Text})"));
    }

    public override IComposable PrepareStmt(string _, string queryTextConstant)
    {
        return new SimpleStatement(Variable.Stmt.AsVar(),
            new SimpleExpression($"{Variable.Client.AsVar()}.prepare({queryTextConstant})"));
    }

    public override SimpleExpression ExecuteStmt(string funcName, SimpleStatement? queryParams)
    {
        var command = $"{Variable.Stmt.AsVar()}.execute";
        if (queryParams is not null)
            command = $"{command}(*{Variable.QueryParams.AsVar()})";
        return new SimpleExpression(command);
    }

    public override MethodDeclaration OneDeclare(string funcName, string queryTextConstant, string argInterface,
        string returnInterface, IList<Parameter> parameters, IList<Column> columns)
    {
        return MethodGen.OneDeclare(funcName, queryTextConstant, argInterface, returnInterface, parameters, columns,
            false, RowDataType.Array);
    }

    public override MethodDeclaration ExecDeclare(string funcName, string queryTextConstant, string argInterface,
        IList<Parameter> parameters)
    {
        return MethodGen.ExecDeclare(funcName, queryTextConstant, argInterface, parameters, false);
    }

    public override MethodDeclaration ManyDeclare(string funcName, string queryTextConstant, string argInterface,
        string returnInterface, IList<Parameter> parameters, IList<Column> columns)
    {
        return MethodGen.ManyDeclare(funcName, queryTextConstant, argInterface, returnInterface, parameters, columns,
            false, RowDataType.Array);
    }
}