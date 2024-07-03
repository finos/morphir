using System;

namespace Morphir.Cli.Commands;

public class DependencyCommands
{
    /// <summary>
    /// Restore dependencies for a project
    /// </summary>
    /// <param name="project"></param>
    public void Restore(String project) => Console.WriteLine("Restoring dependencies...");
}