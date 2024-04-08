using Microsoft.CodeAnalysis.CSharp;
using Microsoft.CodeAnalysis.CSharp.Syntax;
using Plugin;
using static System.String;
using static Microsoft.CodeAnalysis.CSharp.SyntaxFactory;

namespace SqlcGenCsharp.Drivers;

public static class Utils
{
    public static string GetParameterListAsString(string argInterface, IEnumerable<Parameter> parameters)
    {
        return "(" + (IsNullOrEmpty(argInterface) || !parameters.Any() ? Empty : $"{argInterface} args") + ")";
    }
    
    public static ExpressionSyntax AwaitReaderRow()
    {
        return ParseExpression($"await {Variable.Reader.Name()}.ReadAsync()");
    }
    
    public static IEnumerable<StatementSyntax> EstablishConnection()
    {
        return
        [
            ParseStatement(
                $"await using var {Variable.Connection.Name()} = " +
                $"new MySqlConnection({Variable.ConnectionString.Name()});"),
            ParseStatement($"{Variable.Connection.Name()}.Open();")
        ];
    }
    
    public static IEnumerable<StatementSyntax> PrepareSqlCommand(string sqlTextConstant,
        IEnumerable<Parameter> parameters)
    {
        return new[]
        {
            ParseStatement(
                $"await using var {Variable.Command.Name()} = " +
                $"new MySqlCommand({sqlTextConstant}, {Variable.Connection.Name()});")
        }.Concat(
            parameters.Select(param => ParseStatement(
                $"{Variable.Command.Name()}.Parameters.AddWithValue(\"@{param.Column.Name}\", " +
                $"args.{param.Column.Name.FirstCharToUpper()});"))
        );
    }
    
    public static StatementSyntax UsingDataReader()
    {
        return ParseStatement(
            $"await using var {Variable.Reader.Name()} = await {Variable.Command.Name()}.ExecuteReaderAsync();");
    }

    public static InitializerExpressionSyntax GetRecordInitExpression(IEnumerable<Column> columns)
    {
        return InitializerExpression(
            SyntaxKind.ObjectInitializerExpression,
            SeparatedList(columns.Select((column, ordinal) =>
                column.GetReadExpression(ordinal).AssignTo(column.Name.FirstCharToUpper())
            ))
        );
    }
}