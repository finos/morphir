using System.ComponentModel;
using Spectre.Console.Cli;
using Dumpify;
using Spectre.Console;

namespace Morphir.Cli.Commands.Dependency;

public class DependencyFetchCommand: Command<DependencyFetchCommand.Settings>
{
    public sealed class Settings : DependencySettings
    {
        [CommandArgument(0, "[WORKSPACE-OR-PROJECT-PATH]")]
        [Description("The path to the workspace or project to fetch dependencies for.")]
        public string Path { get; set; } = "";
    }

    public override int Execute(CommandContext context, Settings settings)
    {
        AnsiConsole.MarkupLine("Fetching dependencies...");
        settings.Dump();
        return 0;
    }
}