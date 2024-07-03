using ConsoleAppFramework;
using Morphir.Cli.Commands;

namespace Morphir.Cli;

public class Program
{
    public static void Main(string[] args)
    {
        var app = ConsoleApp.Create();
        app.Add<DependencyCommands>("dependency");
        app.Add<ProjectsCommands>("projects");
        app.Run(args);
    }
}