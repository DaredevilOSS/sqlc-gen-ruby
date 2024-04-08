using System.Collections.Immutable;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;
using Google.Protobuf;
using Microsoft.CodeAnalysis;
using Microsoft.CodeAnalysis.CSharp;
using Microsoft.CodeAnalysis.CSharp.Syntax;
using Plugin;
using SqlcGenCsharp.Drivers;
using static Microsoft.CodeAnalysis.CSharp.SyntaxFactory;
using File = Plugin.File;

namespace SqlcGenCsharp;

public record Options
{
    // ReSharper disable once InconsistentNaming
    public required string driver { get; init; }
}

public partial class CodeGenerator
{
    private static readonly char[] Separator = { '/' };

    public CodeGenerator(GenerateRequest generateRequest)
    {
        Options = ParseOptions(generateRequest);
        DbDriver = CreateNodeGenerator(Options.driver);
        GenerateResponse = Generate(generateRequest);
    }

    private Options Options { get; }
    private IDbDriver DbDriver { get; }
    public GenerateResponse GenerateResponse { get; }

    private static Options ParseOptions(GenerateRequest generateRequest)
    {
        var text = Encoding.UTF8.GetString(generateRequest.PluginOptions.ToByteArray());
        return JsonSerializer.Deserialize<Options>(text) ?? throw new InvalidOperationException();
    }

    private static ByteString ToByteString(CompilationUnitSyntax compilationUnit)
    {
        var syntaxTree = CSharpSyntaxTree.Create(compilationUnit);
        var sourceText = syntaxTree.GetText().ToString();
        return ByteString.CopyFromUtf8(sourceText);
    }

    private GenerateResponse Generate(GenerateRequest generateRequest)
    {
        var namespaceName = GenerateNamespace();
        var fileQueries = generateRequest.Queries
            .GroupBy(query => query.Filename)
            .ToImmutableDictionary(
                group => group.Key,
                group => group.ToArray());

        var files = fileQueries.Select(fq => GenerateFile(
            namespaceName, fq.Value, fq.Key));
        return new GenerateResponse { Files = { files } };

        string GenerateNamespace()
        {
            var parts = generateRequest.Settings.Codegen.Out
                .Split(Separator, StringSplitOptions.RemoveEmptyEntries);
            return (parts.Length > 0 ? parts[0] : "GeneratedNamespace") + ".Db";
        }
    }

    private File GenerateFile(string namespaceName, Query[] queries, string filename)
    {
        var (usingDb, className, classDeclaration) = GenerateClass(queries, filename);
        var namespaceDeclaration = FileScopedNamespaceDeclaration(IdentifierName(namespaceName));
        var root = CompilationUnit()
            .AddUsings(usingDb)
            .AddMembers(namespaceDeclaration, classDeclaration)
            .NormalizeWhitespace();

        var compilationUnit = root.WithLeadingTrivia(root.GetLeadingTrivia()
            .Insert(0, Comment($"// auto-generated by sqlc at {DateTime.Now:g} - do not edit"))
            .Insert(1, Whitespace("\n")));

        return new File
        {
            Name = $"{className}.cs",
            Contents = ToByteString(compilationUnit)
        };
    }

    private (UsingDirectiveSyntax[], string, MemberDeclarationSyntax) GenerateClass(Query[] queries, string filename)
    {
        var className = QueryFilenameToClassName(filename);
        var (usingDirectives, sharedMemberDeclarations) = DbDriver.Preamble(className);
        var perQueryMembers = queries.SelectMany(GetMembersForSingleQuery).ToArray();
        return (usingDirectives, className, GetClassDeclaration());

        string QueryFilenameToClassName(string filenameWithExtension)
        {
            return string.Concat(
                Path.GetFileNameWithoutExtension(filenameWithExtension).FirstCharToUpper(),
                Path.GetExtension(filenameWithExtension)[1..].FirstCharToUpper());
        }

        ClassDeclarationSyntax GetClassDeclaration()
        {
            var classDeclaration = (ClassDeclarationSyntax)ParseMemberDeclaration(
                    $"class {className}(string {Variable.ConnectionString.Name()})" + "{}")!
                .AddModifiers(Token(SyntaxKind.PublicKeyword));

            return classDeclaration
                .AddMembers(sharedMemberDeclarations)
                .AddMembers(perQueryMembers);
        }
    }

    private MemberDeclarationSyntax[] GetMembersForSingleQuery(Query query)
    {
        return new[]
            {
                GetQueryTextConstant(query),
                GetQueryColumnsDataclass(query),
                GetQueryParamsDataclass(query),
                AddMethodDeclaration(query)
            }
            .Where(member => member != null)
            .Cast<MemberDeclarationSyntax>()
            .ToArray();
    }

    private MemberDeclarationSyntax AddMethodDeclaration(Query query)
    {
        var queryTextConstant = GetInterfaceName(ClassMemberType.Sql);
        var argInterface = GetInterfaceName(ClassMemberType.Args);
        var returnInterface = GetInterfaceName(ClassMemberType.Row);

        return query.Cmd switch
        {
            ":exec" => DbDriver.ExecDeclare(query.Name, queryTextConstant, argInterface, query.Params),
            ":one" => DbDriver.OneDeclare(query.Name, queryTextConstant, argInterface, returnInterface,
                query.Params, query.Columns),
            ":many" => DbDriver.ManyDeclare(query.Name, queryTextConstant, argInterface, returnInterface,
                query.Params, query.Columns),
            ":execlastid" => DbDriver.ExecLastIdDeclare(query.Name, queryTextConstant, argInterface, returnInterface,
                query.Params, query.Columns),
            _ => throw new InvalidDataException()
        };

        string GetInterfaceName(ClassMemberType classMemberType)
        {
            return $"{query.Name}{classMemberType.Name()}";
        }
    }

    private MemberDeclarationSyntax? GetQueryColumnsDataclass(Query query)
    {
        // TODO add feature-flag for using C# records as data classes or not
        if (query.Columns.Count <= 0) return null;
        var recordParameters = QueryColumnsToRecordParams(query.Columns);
        return GenerateRecord(query.Name, ClassMemberType.Row, recordParameters);
    }

    private ParameterListSyntax QueryColumnsToRecordParams(IEnumerable<Column> columns)
    {
        return ParameterList(SeparatedList(columns
            .Select(column => Parameter(Identifier(column.Name.FirstCharToUpper()))
                .WithType(ParseTypeName(DbDriver.ColumnType(column.Type.Name, column.NotNull)))
            )));
    }

    private MemberDeclarationSyntax? GetQueryParamsDataclass(Query query)
    {
        // TODO add feature-flag for using C# records as data classes or not
        DebugHelper.Append($"query {query.Name} params dataclass?");
        if (query.Params.Count <= 0) return null;
        var recordParameters = QueryColumnsToRecordParams(query.Params.Select(p => p.Column));
        DebugHelper.Append($"query {query.Name} params dataclass created!");
        return GenerateRecord(query.Name, ClassMemberType.Args, recordParameters);
    }

    private static MemberDeclarationSyntax GetQueryTextConstant(Query query)
    {
        return ParseMemberDeclaration(
                $"private const string {query.Name}{ClassMemberType.Sql.Name()} = \"{TransformQuery()}\";")!
            .AppendNewLine();

        string TransformQuery()
        {
            var counter = 0;
            return QueryParameterRegex().Replace(query.Text, m => "@" + query.Params[counter++].Column.Name);
        }
    }

    // TODO find out if needed?
    private IEnumerable<Column> ConstructUpdatedColumns(Query query)
    {
        var colMap = new Dictionary<string, int>();
        return query.Columns
            .Where(column => !string.IsNullOrEmpty(column.Name)) // Filter out columns without a name
            .Select(column =>
            {
                var count = colMap.GetValueOrDefault(column.Name, 0);
                var updatedName = count > 0 ? $"{column.Name}_{count + 1}" : column.Name;
                colMap[column.Name] = count + 1; // Update the count for the current name
                return new Column { Name = updatedName };
            })
            .ToList();
    }

    private static IDbDriver CreateNodeGenerator(string driver)
    {
        return driver switch
        {
            "MySqlConnector" => new MySqlConnectorDriver(),
            _ => throw new ArgumentException($"unknown driver: {driver}", nameof(driver))
        };
    }

    private static RecordDeclarationSyntax GenerateRecord(string name, ClassMemberType classMemberType,
        ParameterListSyntax parameterListSyntax)
    {
        return RecordDeclaration(
                Token(SyntaxKind.StructKeyword),
                $"{name}{classMemberType.Name()}")
            .AddModifiers(
                Token(SyntaxKind.PublicKeyword),
                Token(SyntaxKind.ReadOnlyKeyword),
                Token(SyntaxKind.RecordKeyword)
            )
            .WithParameterList(parameterListSyntax)
            .WithSemicolonToken(Token(SyntaxKind.SemicolonToken));
    }

    [GeneratedRegex(@"\?")]
    private static partial Regex QueryParameterRegex();
}