using Google.Protobuf;
using Microsoft.CodeAnalysis;
using Microsoft.CodeAnalysis.CSharp;
using Microsoft.CodeAnalysis.CSharp.Syntax;
using static Microsoft.CodeAnalysis.CSharp.SyntaxFactory;


namespace SqlcGenCsharp;

public static class Extensions
{
    public static CompilationUnitSyntax AddCommentOnTop(this CompilationUnitSyntax me, string comment)
    {
        return me
            .WithLeadingTrivia(me.GetLeadingTrivia()
                .Insert(0, Comment(comment))
                .Insert(1, Whitespace("\n")));
    }
    
    public static ByteString ToByteString(this CompilationUnitSyntax me)
    {
        var syntaxTree = CSharpSyntaxTree.Create(me);
        var sourceText = syntaxTree.GetText().ToString();
        return ByteString.CopyFromUtf8(sourceText);
    }
}