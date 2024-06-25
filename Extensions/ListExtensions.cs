namespace SqlcGenCsharp;

public static class ListExtensions
{
    public static IEnumerable<T> AppendIfNotNull<T>(this IEnumerable<T> me, T? item)
    {
        return item is not null ? me.Append(item) : me;
    }

    public static string JoinByNewLine(this IEnumerable<string> me, int cnt = 1)
    {
        return string.Join(new string('\n', cnt), me);
    }

    public static string JoinByComma(this IEnumerable<string> me)
    {
        return string.Join(", ", me);
    }

    public static string JoinByCommaAndNewLine(this IEnumerable<string> me)
    {
        return string.Join(",\n", me);
    }
}