using Morphir.Host;

namespace Morphir.Cli;

public class Program
{
    public static int Main(string[] args)
    {
        var hostConfig = new HostConfig("morphir");
        return CommandLineHost.Run(hostConfig, args);
    }
}