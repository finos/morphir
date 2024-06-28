namespace Morphir.Cli.Commands.Run;
using Spectre.Console.Cli;
using Dumpify;
public class RunCommand: Command<RunCommand.Settings>
{
    public sealed class Settings : CommandSettings
    {
        [CommandOption("-i|--include <DEPENDENCY>")]
        public string[] Includes { get; set; } = [];
    }

    public override int Execute(CommandContext context, Settings settings)
    {
        settings.Dump();
        return 0;
    }
}