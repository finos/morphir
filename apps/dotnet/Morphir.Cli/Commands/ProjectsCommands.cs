using System;
using System.ComponentModel;
using System.Threading.Tasks;
using Ookii.CommandLine;
using Ookii.CommandLine.Commands;
using Ookii.CommandLine.Validation;

namespace Morphir.Cli.Commands;

[Command("project")]
[Description("Manage projects")]
internal class ProjectCommand:ParentCommand{}

[GeneratedParser]
[Command("list")]
[ParentCommand(typeof(ProjectCommand))]
[Description("Gets a list of projects")]
internal partial class ListProjectsCommand : AsyncCommandBase
{
    public override async Task<int> RunAsync()
    {
        Console.WriteLine("");
        Console.WriteLine("Listing projects...");
        await Task.CompletedTask;
        return (int)ExitCode.Success;
    }
}
