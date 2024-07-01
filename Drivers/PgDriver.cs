using Plugin;
using RubyCodegen;
using System.Collections.Generic;
using System.Linq;
using System.Text.RegularExpressions;

namespace SqlcGenRuby.Drivers;

public partial class PgDriver : DbDriver
{
    private MethodGen MethodGen { get; }

    public PgDriver()
    {
        MethodGen = new MethodGen(this);
    }

    public override IEnumerable<RequireGem> GetRequiredGems()
    {
        return GetCommonGems()
            .Append(new RequireGem("pg"))
            .Append(new RequireGem("set"));
    }

    public override MethodDeclaration GetInitMethod()
    {
        var connectionPoolInit = new NewObject("ConnectionPool",
            new[] { new SimpleExpression("**connection_pool_params") },
            PgClientCreate());
        return new MethodDeclaration(
            "initialize",
            "Hash[String, String], Hash[String, String]",
            "connection_pool_params, pg_params",
            null,
            [
                new PropertyDeclaration(Variable.Pool.AsProperty(), "untyped", connectionPoolInit),
                new PropertyDeclaration(Variable.PreparedStatements.AsProperty(), "Set[String]", new SimpleExpression("Set[]"))
            ]
        );

        IList<IComposable> PgClientCreate()
        {
            return new List<IComposable>
            {
                new SimpleStatement(
                    Variable.Client.AsVar(),
                    new SimpleExpression("PG.connect(**pg_params)")),
                new SimpleStatement(
                    $"{Variable.Client.AsVar()}.type_map_for_results",
                    new SimpleExpression($"PG::BasicTypeMapForResults.new {Variable.Client.AsVar()}")),
                new SimpleExpression(Variable.Client.AsVar())
            };
        }
    }

    protected override List<(string, HashSet<string>)> GetColumnMapping()
    {
        return
        [
            ("bool", [
                "bool",
                "boolean"
            ]),
            ("Array[Integer]", [
                "binary",
                "bit",
                "bytea",
                "blob",
                "longblob",
                "mediumblob",
                "tinyblob",
                "varbinary"
            ]),
            ("String", [
                "char",
                "date",
                "datetime",
                "longtext",
                "mediumtext",
                "text",
                "bpchar",
                "time",
                "timestamp",
                "tinytext",
                "varchar",
                "json"
            ]),
            ("Integer", [
                "int2",
                "int4",
                "int8",
                "serial",
                "bigserial"
            ]),
            ("Float", [
                "numeric",
                "float4",
                "float8",
                "decimal"
            ])
        ];
    }

    public override PropertyDeclaration QueryTextConstantDeclare(Query query)
    {
        var counter = 1;
        var transformedQueryText = BindRegexToReplace().Replace(query.Text, _ => $"${counter++}");
        return new PropertyDeclaration(
            $"{query.Name}{ClassMember.Sql}",
            "String",
            new SimpleExpression($"%q({transformedQueryText})"));
    }

    public override IComposable PrepareStmt(string funcName, string queryTextConstant)
    {
        return new UnlessCondition(
            $"{Variable.PreparedStatements.AsProperty()}.include?('{funcName}')",
            new List<IComposable>
            {
                new SimpleExpression($"{Variable.Client.AsVar()}.prepare('{funcName}', {queryTextConstant})"),
                new SimpleExpression($"{Variable.PreparedStatements.AsProperty()}.add('{funcName}')")
            }
        );
    }

    public override SimpleExpression ExecuteStmt(string funcName, SimpleStatement? queryParams)
    {
        var queryParamsArg = queryParams is null ? string.Empty : $", {Variable.QueryParams.AsVar()}";
        return new SimpleExpression($"{Variable.Client.AsVar()}.exec_prepared('{funcName}'{queryParamsArg})");
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

    public override MethodDeclaration ExecLastIdDeclare(string funcName, string queryTextConstant,
        string argInterface, IList<Parameter> parameters)
    {
        return MethodGen.ExecLastIdDeclare(funcName, queryTextConstant, argInterface, parameters);
    }

    public override MethodDeclaration ManyDeclare(string funcName, string queryTextConstant, string argInterface,
        string returnInterface, IList<Parameter> parameters, IList<Column> columns)
    {
        return MethodGen.ManyDeclare(funcName, queryTextConstant, argInterface, returnInterface, parameters, columns);
    }

    [GeneratedRegex(@"\?")]
    private static partial Regex BindRegexToReplace();
}