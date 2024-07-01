namespace RubyCodegen;

public interface IComposable
{
    string BuildCode();
}

public interface IRbsType
{
    string BuildType();
}

public interface IComposableRbsType : IComposable, IRbsType;