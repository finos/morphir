using System;
using System.Threading.Tasks;
using ConsoleAppFramework;
using Dumpify;

namespace Morphir.Cli.Commands;

internal class ProjectsCommands
{
    /// <summary>
    /// List all projects in the current workspace
    /// </summary>
    /// <param name="projects">Restricts the listing to only the matching projects.</param>
    [Command("")]
    public Task List([Argument]params string[] projects)
    {
        Console.WriteLine("Listing projects...");
        if (projects.Length > 0)
        {
            projects.Dump("Project Filters");
        }

        // Console.WriteLine($"Command Line Args: {context}");
        //TODO: Implement listing projects
        return Task.CompletedTask;
    }
}