using Plugin;
using RubyCodegen;
using System.Collections.Generic;
using System.Linq;

namespace SqlcGenCsharp.Drivers;

public class MethodGen(DbDriver dbDriver)
{
    public static MethodDeclaration OneDeclare(string funcName, string queryTextConstant, string argInterface,
        string returnInterface, IList<Parameter> parameters, IList<Column> columns)
    {
        var newObjectExpression = new NewObject(returnInterface, GetColumnsInitExpressions(columns));
        IEnumerable<IComposable> withResourceBody = new List<IComposable>();
        var queryParams = GetQueryParams(argInterface, parameters);
        withResourceBody = withResourceBody.AppendIfNotNull(queryParams);
        withResourceBody = withResourceBody.Concat(
            [
                PrepareQuery(queryTextConstant),
                ExecuteAndAssign(queryTextConstant, queryParams),
                new SimpleStatement(Variable.Row.AsVar(), new SimpleExpression($"{Variable.Result.AsVar()}.first")),
                new SimpleExpression($"return nil if {Variable.Row.AsVar()}.nil?"),
                new SimpleStatement($"{Variable.Entity.AsVar()}", newObjectExpression),
                new SimpleExpression($"return {Variable.Entity.AsVar()}")
            ]
        );

        return new MethodDeclaration(funcName, GetMethodArgs(argInterface, parameters),
            new List<IComposable>
            {
                new WithResource(Variable.Pool.AsProperty(), Variable.Client.AsVar(), withResourceBody)
            });
    }

    private static string? GetMethodArgs(string argInterface, IList<Parameter> parameters)
    {
        return parameters.Count == 0 ? null : argInterface.SnakeCase();
    }

    public static MethodDeclaration ManyDeclare(string funcName, string queryTextConstant, string argInterface,
        string returnInterface, IList<Parameter> parameters, IList<Column> columns)
    {
        var listAppend = new ListAppend(Variable.Entities.AsVar(),
            new NewObject(returnInterface, GetColumnsInitExpressions(columns)));
        IEnumerable<IComposable> withResourceBody = new List<IComposable>();
        var queryParams = GetQueryParams(argInterface, parameters);
        withResourceBody = withResourceBody.AppendIfNotNull(queryParams);
        withResourceBody = withResourceBody.Concat(
            [
                PrepareQuery(queryTextConstant),
                ExecuteAndAssign(queryTextConstant, queryParams),
                new SimpleStatement(Variable.Entities.AsVar(), new SimpleExpression("[]")),
                new ForeachLoop(Variable.Result.AsVar(), Variable.Row.AsVar(), new List<IComposable> { listAppend }),
                new SimpleExpression($"return {Variable.Entities.AsVar()}")
            ]
        );

        return new MethodDeclaration(funcName, GetMethodArgs(argInterface, parameters),
            new List<IComposable>
            {
                new WithResource(Variable.Pool.AsProperty(), Variable.Client.AsVar(), withResourceBody)
            });
    }

    public static MethodDeclaration ExecDeclare(string funcName, string queryTextConstant, string argInterface,
        IList<Parameter> parameters)
    {
        IEnumerable<IComposable> withResourceBody = new List<IComposable>();
        var queryParams = GetQueryParams(argInterface, parameters);
        withResourceBody = withResourceBody.AppendIfNotNull(queryParams);
        withResourceBody = withResourceBody.Concat(
            [
                PrepareQuery(queryTextConstant),
                ExecuteStmt(queryTextConstant, queryParams)
            ]
        );
        return new MethodDeclaration(funcName, GetMethodArgs(argInterface, parameters),
            new List<IComposable>
            {
                new WithResource(Variable.Pool.AsProperty(), Variable.Client.AsVar(), withResourceBody)
            });
    }

    public static MethodDeclaration ExecLastIdDeclare(string funcName, string queryTextConstant, string argInterface,
        IList<Parameter> parameters)
    {
        IEnumerable<IComposable> withResourceBody = new List<IComposable>();
        var queryParams = GetQueryParams(argInterface, parameters);
        withResourceBody = withResourceBody.AppendIfNotNull(queryParams);
        withResourceBody = withResourceBody.Concat(
            [
                PrepareQuery(queryTextConstant),
                ExecuteStmt(queryTextConstant, queryParams),
                new SimpleExpression($"return {Variable.Client.AsVar()}.last_id")
            ]
        );
        return new MethodDeclaration(funcName, GetMethodArgs(argInterface, parameters),
            new List<IComposable>
            {
                new WithResource(Variable.Pool.AsProperty(), Variable.Client.AsVar(), withResourceBody)
            });
    }

    private static SimpleStatement? GetQueryParams(string argInterface, IList<Parameter> parameters)
    {
        var queryParams = parameters.Select(p => $"{argInterface}.{p.Column.Name}").ToList();
        return queryParams.Count == 0
            ? null
            : new SimpleStatement(Variable.QueryParams.AsVar(), new SimpleExpression($"[{queryParams.JoinByComma()}]"));
    }

    private static SimpleStatement PrepareQuery(string queryTextConstant)
    {
        return new SimpleStatement(Variable.Stmt.AsVar(),
            new SimpleExpression($"{Variable.Client.AsVar()}.prepare({queryTextConstant})"));
    }

    private static SimpleExpression ExecuteStmt(string queryTextConstant, SimpleStatement? queryParams)
    {
        var queryParamsArg = queryParams is null ? string.Empty : $", {Variable.QueryParams.AsVar()}";
        return new SimpleExpression($"{Variable.Stmt.AsVar()}.execute({queryTextConstant}{queryParamsArg})");
    }

    private static IEnumerable<SimpleExpression> GetColumnsInitExpressions(IEnumerable<Column> columns)
    {
        return columns.Select(c => new SimpleExpression($"{Variable.Row.AsVar()}['{c.Name}']"));
    }

    private static SimpleStatement ExecuteAndAssign(string queryTextConstant, SimpleStatement? queryParams)
    {
        return new SimpleStatement(Variable.Result.AsVar(), ExecuteStmt(queryTextConstant, queryParams));
    }
}