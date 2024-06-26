using Plugin;
using RubyCodegen;
using System.Collections.Generic;
using System.Linq;
using System.Text.RegularExpressions;

namespace SqlcGenCsharp.Drivers;

public partial class PgDriver : DbDriver
{
    private MethodGen MethodGen { get; }

    public PgDriver()
    {
        MethodGen = new MethodGen(this);
    }

    public override IEnumerable<RequireGem> GetRequiredGems()
    {
        return GetCommonGems().Append(new RequireGem("pg"));
    }

    public override MethodDeclaration GetInitMethod()
    {
        return new MethodDeclaration("initialize", "connection_pool_params, pg_params",
            [
                new SimpleStatement(Variable.Pool.AsProperty(), new SimpleExpression(
                    "ConnectionPool::new(**connection_pool_params) { PG.connect(**pg_params) }"))
            ]
        );
    }

    public override SimpleStatement QueryTextConstantDeclare(Query query)
    {
        var counter = 1;
        var transformedQueryText = StandardBindRegex().Replace(query.Text, m => $"${counter++}");
        return new SimpleStatement($"{query.Name}{ClassMember.Sql}",
            new SimpleExpression($"%q({transformedQueryText})"));
    }

    public override SimpleStatement PrepareStmt(string funcName, string queryTextConstant)
    {
        return new SimpleStatement("_",
            new SimpleExpression($"{Variable.Client.AsVar()}.prepare('{funcName}', {queryTextConstant})"));
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
    private static partial Regex StandardBindRegex();
}