using Plugin;
using RubyCodegen;
using System.Collections.Generic;
using System.Linq;

namespace SqlcGenRuby.Drivers;

public class MethodGen(DbDriver dbDriver)
{
    private static string? GetMethodArgs(string argInterface, IList<Parameter> parameters)
    {
        return parameters.Count == 0 ? null : argInterface.SnakeCase();
    }

    public MethodDeclaration OneDeclare(string funcName, string queryTextConstant, string argInterface,
        string returnInterface, IList<Parameter> parameters, IList<Column> columns, bool poolingEnabled = true,
        RowDataType rowDataType = RowDataType.Hash)
    {
        var newObjectExpression = new NewObject(returnInterface, GetColumnsInitExpressions(columns, rowDataType));
        IEnumerable<IComposable> withResourceBody = new List<IComposable>();
        var queryParams = GetQueryParams(argInterface, parameters);
        withResourceBody = withResourceBody.AppendIfNotNull(queryParams);
        withResourceBody = withResourceBody
            .Concat(
                [
                    dbDriver.PrepareStmt(funcName, queryTextConstant),
                    ExecuteAndAssign(funcName, queryParams),
                    new SimpleStatement(Variable.Row.AsVar(), new SimpleExpression($"{Variable.Result.AsVar()}.first")),
                    new SimpleExpression($"return nil if {Variable.Row.AsVar()}.nil?"),
                    new SimpleStatement($"{Variable.Entity.AsVar()}", newObjectExpression),
                    new SimpleExpression($"return {Variable.Entity.AsVar()}")
                ]
            ).ToList();

        var methodArgs = GetMethodArgs(argInterface, parameters);
        var methodBody = OptionallyAddPoolUsage(poolingEnabled, withResourceBody);
        return new MethodDeclaration(funcName, argInterface, methodArgs, $"{returnInterface}?", methodBody);
    }

    private static IEnumerable<IComposable> OptionallyAddPoolUsage(bool poolingEnabled, IEnumerable<IComposable> body)
    {
        return poolingEnabled
            ?
            [
                new WithResource(
                    Variable.Db.AsProperty(),
                    Variable.Client.AsVar(),
                    body.ToList())
            ]
            : new List<IComposable>
                {
                    new SimpleExpression($"{Variable.Client.AsVar()} = {Variable.Db.AsProperty()}")
                }
                .Concat(body);
    }

    public MethodDeclaration ManyDeclare(string funcName, string queryTextConstant, string argInterface,
        string returnInterface, IList<Parameter> parameters, IList<Column> columns, bool poolingEnabled = true,
        RowDataType rowDataType = RowDataType.Hash)
    {
        var queryParams = GetQueryParams(argInterface, parameters);
        var withResourceBody = new List<IComposable>()
            .AppendIfNotNull(queryParams)
            .Append(dbDriver.PrepareStmt(funcName, queryTextConstant))
            .Append(ExecuteAndAssign(funcName, queryParams))
            .Append(new SimpleStatement(Variable.Entities.AsVar(), new SimpleExpression("[]")))
            .Append(AssignResultInForeach())
            .Append(new SimpleExpression($"return {Variable.Entities.AsVar()}"));

        var methodArgs = GetMethodArgs(argInterface, parameters);
        var methodBody = OptionallyAddPoolUsage(poolingEnabled, withResourceBody);
        return new MethodDeclaration(funcName, argInterface, methodArgs, null, methodBody);

        ForeachLoop AssignResultInForeach()
        {
            var listAppend = new ListAppend(Variable.Entities.AsVar(),
                new NewObject(returnInterface, GetColumnsInitExpressions(columns, rowDataType)));
            return new ForeachLoop(
                Variable.Result.AsVar(),
                Variable.Row.AsVar(),
                new List<IComposable> { listAppend });
        }
    }

    public MethodDeclaration ExecDeclare(string funcName, string queryTextConstant, string argInterface,
        IList<Parameter> parameters, bool poolingEnabled = true)
    {
        var queryParams = GetQueryParams(argInterface, parameters);
        var withResourceBody = new List<IComposable>()
            .AppendIfNotNull(queryParams)
            .Append(dbDriver.PrepareStmt(funcName, queryTextConstant))
            .Append(dbDriver.ExecuteStmt(funcName, queryParams))
            .ToList();

        var methodArgs = GetMethodArgs(argInterface, parameters);
        var methodBody = OptionallyAddPoolUsage(poolingEnabled, withResourceBody);
        return new MethodDeclaration(funcName, argInterface, methodArgs, null, methodBody);
    }

    public MethodDeclaration ExecLastIdDeclare(string funcName, string queryTextConstant, string argInterface,
        IList<Parameter> parameters)
    {
        var queryParams = GetQueryParams(argInterface, parameters);
        var withResourceBody = new List<IComposable>()
            .AppendIfNotNull(queryParams)
            .Append(dbDriver.PrepareStmt(funcName, queryTextConstant))
            .Append(dbDriver.ExecuteStmt(funcName, queryParams))
            .Append(new SimpleExpression($"return {Variable.Client.AsVar()}.last_id"));

        return new MethodDeclaration(
            funcName,
            argInterface,
            GetMethodArgs(argInterface, parameters),
            "Integer",
            new List<IComposable>
            {
                new WithResource(Variable.Db.AsProperty(), Variable.Client.AsVar(),
                    withResourceBody.ToList())
            }
        );
    }

    private static SimpleStatement? GetQueryParams(string argInterface, IList<Parameter> parameters)
    {
        var queryParams = parameters.Select(p => $"{argInterface.SnakeCase()}.{p.Column.Name}").ToList();
        return queryParams.Count == 0
            ? null
            : new SimpleStatement(Variable.QueryParams.AsVar(),
                new SimpleExpression($"[{queryParams.JoinByCommaAndFormat()}]"));
    }

    private static IList<SimpleExpression> GetColumnsInitExpressions(IList<Column> columns, RowDataType rowDataType)
    {
        return rowDataType == RowDataType.Hash
            ? columns.Select(c => new SimpleExpression($"{Variable.Row.AsVar()}['{c.Name}']")).ToList()
            : columns.Select((_, i) => new SimpleExpression($"{Variable.Row.AsVar()}[{i}]")).ToList();
    }

    private SimpleStatement ExecuteAndAssign(string funcName, SimpleStatement? queryParams)
    {
        return new SimpleStatement(Variable.Result.AsVar(),
            dbDriver.ExecuteStmt(funcName, queryParams));
    }
}