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
        return new MethodDeclaration("initialize", "connection_pool_params, mysql2_params",
            [
                new SimpleStatement(Variable.Pool.AsProperty(), new SimpleExpression(
                    "ConnectionPool::new(**connection_pool_params) { Mysql2::Client.new(**mysql2_params) }"))
            ]
        );
    }

    public override SimpleStatement QueryTextConstantDeclare(Query query)
    {
        return new SimpleStatement($"{query.Name}{ClassMember.Sql}", new SimpleExpression($"%q({query.Text})"));
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