using System.Text.RegularExpressions;

namespace SqlcGenCsharp;

public static partial class StringExtensions
{
    public static string FirstCharToUpper(this string input)
    {
        return input switch
        {
            null => throw new ArgumentNullException(nameof(input)),
            "" => throw new ArgumentException($"{nameof(input)} cannot be empty", nameof(input)),
            _ => string.Concat(input[0].ToString().ToUpper(), input.AsSpan(1))
        };
    }

    public static string FirstCharToLower(this string input)
    {
        return input switch
        {
            null => throw new ArgumentNullException(nameof(input)),
            "" => throw new ArgumentException($"{nameof(input)} cannot be empty", nameof(input)),
            _ => string.Concat(input[0].ToString().ToLower(), input.AsSpan(1))
        };
    }

    public static string SnakeCase(this string input)
    {
        return string.IsNullOrEmpty(input)
            ? input
            : MyRegex().Replace(input, "_$1").TrimStart('_').ToLower();
    }

    public static string TrimTrailingWhitespacesPerLine(this string lines)
    {
        var lengthToRemove = lines
            .Split("\n")
            .First()
            .FirstNonWhitespaceIndex();
        return lines
            .Split("\n")
            .Select(l => l[lengthToRemove..])
            .JoinByNewLine();
    }

    public static string Indent(this string lines)
    {
        return lines
            .Split("\n")
            .Select(line => $"\t{line}")
            .JoinByNewLine();
    }

    private static int FirstNonWhitespaceIndex(this string input)
    {
        if (string.IsNullOrEmpty(input))
            return -1;
        var trimmed = input.TrimStart();
        return trimmed.Length == 0 ? -1 : input.Length - trimmed.Length;
    }


    [GeneratedRegex("([A-Z])")]
    private static partial Regex MyRegex();
}