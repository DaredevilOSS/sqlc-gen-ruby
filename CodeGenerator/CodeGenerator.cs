using Google.Protobuf;
using Plugin;
using RubyCodegen;
using SqlcGenCsharp.Drivers;
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Threading.Tasks;
using File = Plugin.File;

namespace SqlcGenCsharp;

public class CodeGenerator
{
    private DbDriver? _dbDriver;
    private Options? _options;

    private Options Options
    {
        get => _options!;
        set => _options = value;
    }

    private DbDriver DbDriver
    {
        get => _dbDriver!;
        set => _dbDriver = value;
    }

    private void InitGenerators(GenerateRequest generateRequest)
    {
        Options = new Options(generateRequest);
        DbDriver = InstantiateDriver();
    }

    private DbDriver InstantiateDriver()
    {
        return Options.DriverName switch
        {
            DriverName.Mysql2 => new Mysql2Driver(),
            DriverName.Pg => new PgDriver(),
            _ => throw new ArgumentException($"unknown driver: {Options.DriverName}")
        };
    }

    public Task<GenerateResponse> Generate(GenerateRequest generateRequest)
    {
        InitGenerators(generateRequest); // the request is necessary in order to know which generators are needed
        var fileQueries = GetFileQueries();
        var files = fileQueries
            .Select(fq => GenerateFile(fq.Value, fq.Key))
            .Append(GenerateGemfile());

        return Task.FromResult(new GenerateResponse { Files = { files } });

        Dictionary<string, Query[]> GetFileQueries()
        {
            return generateRequest.Queries
                .GroupBy(query =>
                    Options.FilePerQuery
                        ? $"{query.Name}Query"
                        : QueryFilenameToClassName(query.Filename))
                .ToDictionary(
                    group => group.Key,
                    group => group.ToArray());
        }

        string QueryFilenameToClassName(string filenameWithExtension)
        {
            return string.Concat(
                Path.GetFileNameWithoutExtension(filenameWithExtension).FirstCharToUpper(),
                Path.GetExtension(filenameWithExtension)[1..].FirstCharToUpper());
        }
    }
    
    private File GenerateFile(IEnumerable<Query> queries, string className)
    {
        var (requiredGems, classDeclaration) = GenerateClass(queries, className);
        var contents = $"""
                        {Consts.AutoGeneratedComment}
                        {requiredGems.Select(r => r.Build()).JoinByNewLine()}

                        {classDeclaration.Build()}
                        """;

        return new File { Name = $"{className.SnakeCase()}.rb", Contents = ByteString.CopyFromUtf8(contents) };
    }

    private File GenerateGemfile()
    {
        var requireGems = DbDriver.GetRequiredGems().Select(gem => $"gem '{gem.GetName()}'").JoinByNewLine();
        return new File
        {
            Name = "Gemfile",
            Contents = ByteString.CopyFromUtf8($"""
                                                source 'https://rubygems.org'

                                                {requireGems}
                                                """)
        };
    }

    private (IEnumerable<RequireGem>, ClassDeclaration) GenerateClass(IEnumerable<Query> queries, string className)
    {
        var requiredGems = DbDriver.GetRequiredGems();
        var initMethod = DbDriver.GetInitMethod();
        var queryMembers = queries
            .SelectMany(q =>
            {
                IEnumerable<IComposable> members = new List<IComposable>();
                members = members.Append(GetQueryTextConstant(q));
                members = members.AppendIfNotNull(GetQueryColumnsDataclass(q));
                members = members.AppendIfNotNull(GetQueryParamsDataclass(q));
                members = members.Append(GetMethodDeclaration(q));
                return members;
            });
        var classMembers = new[] { initMethod }.Concat(queryMembers);
        return (requiredGems, new ClassDeclaration(className, classMembers));
    }

    private static SimpleStatement GenerateDataclass(string name, ClassMember classMember, IEnumerable<Column> columns,
        Options options)
    {
        var dataclassName = $"{name.FirstCharToUpper()}{classMember.Name()}";
        var dataColumns = columns.Select(c => $":{c.Name.ToLower()}").JoinByCommaAndNewLine();
        return new SimpleStatement(dataclassName,
            new SimpleExpression(options.RubyMajorVersion.LatestRubySupported()
                ? $"Struct.new(\n{dataColumns.Indent()}\n)"
                : $"Data.define(\n{dataColumns.Indent()}\n)"));
    }

    private SimpleStatement? GetQueryColumnsDataclass(Query query)
    {
        if (query.Columns.Count <= 0)
        {
            return null;
        }

        return query.Columns.Count <= 0
            ? null
            : GenerateDataclass(query.Name, ClassMember.Row, query.Columns, Options);
    }

    private SimpleStatement? GetQueryParamsDataclass(Query query)
    {
        if (query.Params.Count <= 0)
        {
            return null;
        }

        var columns = query.Params.Select(p => p.Column);
        return GenerateDataclass(query.Name, ClassMember.Args, columns, Options);
    }

    private static SimpleStatement GetQueryTextConstant(Query query)
    {
        return new SimpleStatement($"{query.Name}{ClassMember.Sql}", new SimpleExpression($"%q({query.Text})"));
    }

    private MethodDeclaration GetMethodDeclaration(Query query)
    {
        var queryTextConstant = GetInterfaceName(ClassMember.Sql);
        var argInterface = GetInterfaceName(ClassMember.Args).SnakeCase();
        var returnInterface = GetInterfaceName(ClassMember.Row);
        var funcName = query.Name.SnakeCase();

        return query.Cmd switch
        {
            ":one" => DbDriver.OneDeclare(funcName, queryTextConstant, argInterface, returnInterface,
                query.Params, query.Columns),
            ":many" => DbDriver.ManyDeclare(funcName, queryTextConstant, argInterface, returnInterface,
                query.Params, query.Columns),
            ":exec" => DbDriver.ExecDeclare(funcName, queryTextConstant, argInterface, query.Params),
            ":execlastid" => DbDriver.ExecLastIdDeclare(funcName, queryTextConstant, argInterface, query.Params),
            _ => throw new InvalidDataException()
        };

        string GetInterfaceName(ClassMember classMemberType)
        {
            return $"{query.Name}{classMemberType.Name()}";
        }
    }
}