using System;
using System.ComponentModel;
using System.Threading.Tasks;
using Ookii.CommandLine;
using Ookii.CommandLine.Commands;

namespace Morphir.Cli.Commands;

[Command("dep")]
[Description("Manage dependencies.")]
internal class DependencyCommand:ParentCommand{}

[GeneratedParser]
[Command("restore")]
[ParentCommand(typeof(DependencyCommand))]
[Description("Restore project and workspace dependencies.")]
internal partial class RestoreDependenciesCommand: AsyncCommandBase
{
    /// <summary>
    /// Restore dependencies for a project
    /// </summary>
    /// <param name="project"></param>
    public override async Task<int> RunAsync()
    {
        Console.WriteLine("Restoring dependencies...");
        await Task.CompletedTask;
        return (int)ExitCode.Success;
    }
}