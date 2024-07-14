using Plugin;
using RubyCodegen;
using System.Collections.Generic;
using System.Linq;

namespace SqlcGenRuby.Drivers;

public class Mysql2Driver : DbDriver
{
    private MethodGen MethodGen { get; }

    public Mysql2Driver()
    {
        MethodGen = new MethodGen(this);
    }

    public override IEnumerable<RequireGem> GetRequiredGems()
    {
        return GetCommonGems().Append(new RequireGem("mysql2"));
    }

    public override MethodDeclaration GetInitMethod()
    {
        var connectionPoolInit = new NewObject("ConnectionPool",
            new[] { new SimpleExpression("**connection_pool_params") },
            new List<IComposable> { new SimpleExpression("Mysql2::Client.new(**mysql2_params)") });
        return new MethodDeclaration(
            "initialize",
            "Hash[String, String], Hash[String, String]",
            "connection_pool_params, mysql2_params",
            null,
            [
                new PropertyDeclaration(Variable.Db.AsProperty(), "untyped", connectionPoolInit)
            ]
        );
    }

    protected override IEnumerable<ColumnMappingConfig> GetColumnMapping()
    {
        return
        [
            new ColumnMappingConfig("Array[Integer]", [
                "binary",
                "bit",
                "blob",
                "longblob",
                "mediumblob",
                "tinyblob",
                "varbinary"
            ], false),
            new ColumnMappingConfig("String", [
                "char",
                "date",
                "datetime",
                "decimal",
                "longtext",
                "mediumtext",
                "text",
                "time",
                "timestamp",
                "tinytext",
                "varchar",
                "json"
            ], false),
            new ColumnMappingConfig("Integer", [
                "bigint",
                "int",
                "mediumint",
                "smallint",
                "tinyint",
                "year"
            ], false),
            new ColumnMappingConfig("Float", ["double", "float"], false),
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
        return MethodGen.OneDeclare(funcName, queryTextConstant, argInterface, returnInterface, parameters, columns);
    }

    public override MethodDeclaration ExecDeclare(string funcName, string queryTextConstant, string argInterface,
        IList<Parameter> parameters)
    {
        return MethodGen.ExecDeclare(funcName, queryTextConstant, argInterface, parameters);
    }

    public MethodDeclaration ExecLastIdDeclare(string funcName, string queryTextConstant,
        string argInterface, IList<Parameter> parameters)
    {
        return MethodGen.ExecLastIdDeclare(funcName, queryTextConstant, argInterface, parameters);
    }

    public override MethodDeclaration ManyDeclare(string funcName, string queryTextConstant, string argInterface,
        string returnInterface, IList<Parameter> parameters, IList<Column> columns)
    {
        return MethodGen.ManyDeclare(funcName, queryTextConstant, argInterface, returnInterface, parameters, columns);
    }
}