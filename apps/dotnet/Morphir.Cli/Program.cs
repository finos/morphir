using System.Reflection;
using Morphir.Cli;
using Morphir.Cli.Commands;
using Ookii.CommandLine;
using Ookii.CommandLine.Commands;

[assembly: ApplicationFriendlyName("Morphir CLI")]


var options = new CommandOptions()
{
    CommandNameTransform = NameTransform.DashCase,
    UsageWriter = new UsageWriter()
    {
        IncludeApplicationDescriptionBeforeCommandList = true,
    }
};

var manager = new GeneratedManager(options);
return await manager.RunCommandAsync() ?? (int)ExitCode.GeneralFailure;