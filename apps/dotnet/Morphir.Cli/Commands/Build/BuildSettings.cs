using System.ComponentModel;
using Spectre.Console;
using Spectre.Console.Cli;

namespace Morphir.Cli.Commands.Build;

public class BuildSettings: CommandSettings
{
    [CommandOption("-t|--target <TARGET>")]
    [Description("The targets to build.")]
    public string[] Targets { get; set; } = ["make"];

    public override ValidationResult Validate()
    {
        if (Targets.Length == 0)
        {
            AnsiConsole.MarkupLine("[red]No targets specified[/]");
            return ValidationResult.Error("No targets specified");
        }
        return base.Validate();
    }
}