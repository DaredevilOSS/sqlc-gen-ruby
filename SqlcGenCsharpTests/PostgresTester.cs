using System;
using System.Threading.Tasks;
using NpgsqlExample;
using NUnit.Framework;
using NUnit.Framework.Legacy;

namespace SqlcGenCsharpTests;

[TestFixture]
public class PostgresTester : DriverTester
{
    private static string ConnectionStringEnv => "POSTGRES_CONNECTION_STRING";

    private QuerySql QuerySql { get; } =
        new(Environment.GetEnvironmentVariable(ConnectionStringEnv)!);

    [Test]
    public async Task TestFlowOnDriver() { await TestFlow(); }

    protected override async Task<long> CreateFirstAuthorAndTest()
    {
        var bojackCreateAuthorArgs = new QuerySql.CreateAuthorArgs
        {
            Name = Consts.BojackAuthor,
            Bio = Consts.BojackTheme
        };
        var createdBojackAuthor = await QuerySql.CreateAuthor(bojackCreateAuthorArgs);
        Assert.That(createdBojackAuthor is
        {
            Name: Consts.BojackAuthor,
            Bio: Consts.BojackTheme
        });
        var bojackInsertedId = createdBojackAuthor!.Value.Id;
        var getAuthorArgs = new QuerySql.GetAuthorArgs
        {
            Id = bojackInsertedId
        };
        var singleAuthor = await QuerySql.GetAuthor(getAuthorArgs);
        Assert.That(singleAuthor is
        {
            Name: Consts.BojackAuthor,
            Bio: Consts.BojackTheme
        });
        return bojackInsertedId;
    }

    protected override async Task CreateSecondAuthorAndTest()
    {
        var createAuthorArgs = new QuerySql.CreateAuthorArgs
        {
            Name = Consts.DrSeussAuthor,
            Bio = Consts.DrSeussQuote
        };
        await QuerySql.CreateAuthor(createAuthorArgs);
        var authors = await QuerySql.ListAuthors();
        Assert.That(authors[0] is
        {
            Name: Consts.BojackAuthor,
            Bio: Consts.BojackTheme
        });
        Assert.That(authors[1] is
        {
            Name: Consts.DrSeussAuthor,
            Bio: Consts.DrSeussQuote
        });
        ClassicAssert.AreEqual(2, authors.Count);
    }

    protected override async Task DeleteFirstAuthorAndTest(long idToDelete)
    {
        var deleteAuthorArgs = new QuerySql.DeleteAuthorArgs
        {
            Id = idToDelete
        };
        await QuerySql.DeleteAuthor(deleteAuthorArgs);
        var authorRows = await QuerySql.ListAuthors();
        Assert.That(authorRows[0] is
        {
            Name: Consts.DrSeussAuthor,
            Bio: Consts.DrSeussQuote
        });
        ClassicAssert.AreEqual(1, authorRows.Count);
    }
}