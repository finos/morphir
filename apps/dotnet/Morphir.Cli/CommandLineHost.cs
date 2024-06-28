using System.Collections.Generic;
using Morphir.Cli.Commands.Dependency;
using Morphir.Host;
using Spectre.Console.Cli;

namespace Morphir.Cli;

public class CommandLineHost(HostConfig hostConfig)
{
    private CommandApp _app = CreateApp(hostConfig);

    private static CommandApp CreateApp(HostConfig hostConfig)
    {
        var app = new CommandApp();
        app.Configure(config =>
        {
            config.AddCommand<Commands.Build.BuildCommand>("build")
                .WithDescription("Build the project");
            config.AddCommand<Commands.Run.RunCommand>("run")
                .WithDescription("Run the project");
            config.AddBranch<DependencySettings>("dependency", dependencyConfig =>
            {
                dependencyConfig.AddCommand<DependencyFetchCommand>("fetch")
                    .WithDescription("Fetch dependencies");
            });
        });
        return app;
    }
    
    public int Run(IEnumerable<string> args) => _app.Run(args);
    
    public static int Run(HostConfig hostConfig, IEnumerable<string> args) => new CommandLineHost(hostConfig).Run(args);
}