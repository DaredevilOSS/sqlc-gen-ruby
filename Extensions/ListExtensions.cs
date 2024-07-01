namespace SqlcGenRuby;

public static class ListExtensions
{
    private const int MaxElementsPerLine = 5;

    public static IEnumerable<T> AppendIfNotNull<T>(this IEnumerable<T> me, T? item)
    {
        return item is not null ? me.Append(item) : me;
    }

    public static string JoinByNewLine(this IEnumerable<string> me, int cnt = 1)
    {
        return string.Join(new string('\n', cnt), me);
    }

    public static string JoinByCommaAndFormat(this IList<string> me)
    {
        return me.Count < MaxElementsPerLine
            ? string.Join(", ", me)
            : $"\n{string.Join(",\n", me).Indent()}\n";
    }
}