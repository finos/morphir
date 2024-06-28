using Dumpify;
using Spectre.Console;
using Spectre.Console.Cli;

namespace Morphir.Cli.Commands.Build;

public class BuildCommand: Command<BuildSettings>
{
    public override int Execute(CommandContext context, BuildSettings settings)
    {
        AnsiConsole.Write("Building...");
        settings.Dump();
        return 0;
    }
}