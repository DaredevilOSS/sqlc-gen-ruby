using Plugin;
using RubyCodegen;
using System.Collections.Generic;
using System.Linq;
using System.Text.RegularExpressions;

namespace SqlcGenCsharp.Drivers;

public partial class Mysql2Driver : DbDriver
{
    public override MethodDeclaration GetInitMethod()
    {
        return new MethodDeclaration("initialize", "connection_pool_params, mysql2_params",
            [
                new NewObject("ConnectionPool", [new SimpleExpression("**connection_pool_params")],
                    new SimpleStatement("@pool", new NewObject(
                            "Mysql2::Client", [new SimpleExpression("**mysql2_params")], null
                        )
                    )
                )
            ]
        );
    }

    public override IEnumerable<RequireGem> GetRequiredGems()
    {
        return GetCommonGems().Append(new RequireGem("mysql2"));
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