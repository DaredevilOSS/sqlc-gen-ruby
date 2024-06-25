using Plugin;
using RubyCodegen;
using System.Collections.Generic;

namespace SqlcGenCsharp.Drivers;

public abstract class DbDriver
{
    protected static IEnumerable<RequireGem> GetCommonGems()
    {
        return [new RequireGem("connection_pool")];
    }

    public abstract IEnumerable<RequireGem> GetRequiredGems();

    public abstract MethodDeclaration GetInitMethod();

    public abstract SimpleStatement PrepareStmt(string funcName, string queryTextConstant);

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