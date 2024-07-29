using Dunet;
using Morphir.CodeModel.Common;
using Vogen;

namespace Morphir.CodeModel.ProjectSystems;

[ValueObject<string>]
public partial struct ProjectName
{
}

[ValueObject<string>]
public partial struct SourceDirectoryPath
{
}

public record DecorationInfo(
    DisplayName DisplayName,
    EntryPoint EntryPoint,
    IRLocation IR,
    StorageLocation StorageLocation);

public record MorphirProject(
    ProjectName Name,
    SourceDirectoryPath SourceDirectory,
    IReadOnlyList<LocalDependency> LocalDependencies,
    IReadOnlyList<Dependency> Dependencies);

[Union]
public partial record EntryPoint
{
    partial record ByFQName(string FQName);
}

[Union]
public partial record IRLocation
{
}

[Union]
public partial record StorageLocation
{
}

[Union]
public partial record LocalDependency
{
    partial record FromPath(string PathString);
}

[Union]
public partial record Dependency
{
    partial record FromPath(string PathString);
}