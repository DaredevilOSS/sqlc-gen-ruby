using Plugin;
using RubyCodegen;
using System.Collections.Generic;
using System.Linq;

namespace SqlcGenCsharp.Drivers;

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
        return new MethodDeclaration("initialize", "connection_pool_params, mysql2_params",
            [
                new SimpleStatement(Variable.Pool.AsProperty(),
                    new NewObject("ConnectionPool", [new SimpleExpression("**connection_pool_params")],
                        new SimpleExpression("new Mysql2::Client(**mysql2_params)")))
            ]
        );
    }

    public override SimpleStatement PrepareStmt(string funcName, string queryTextConstant)
    {
        return new SimpleStatement(Variable.Stmt.AsVar(),
            new SimpleExpression($"{Variable.Client.AsVar()}.prepare('{funcName}', {queryTextConstant})"));
    }

    public override SimpleExpression ExecuteStmt(string funcName, SimpleStatement? queryParams)
    {
        var queryParamsArg = queryParams is null ? string.Empty : $", {Variable.QueryParams.AsVar()}";
        return new SimpleExpression($"{Variable.Stmt.AsVar()}.execute('{funcName}'{queryParamsArg})");
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
}