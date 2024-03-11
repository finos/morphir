#r "nuget:Microsoft.Extensions.Logging"
#r "nuget:Microsoft.Extensions.DependencyInjection"
#r "nuget:Fun.Blazor"

open Microsoft.Extensions.DependencyInjection
open Fun.Blazor
open Fun.Css

let serviceProvider = ServiceCollection().AddLogging().BuildServiceProvider()

fragment {
    doctype "html5"
    html' {
        lang "en"
        head {
            title { "Fun.Blazor" }
            chartsetUTF8
        }
        body {
            h1 {
                style { color color.green }
                "Cool script"
            }
        }
    }
}
|> html.renderAsString serviceProvider
|> Async.AwaitTask
|> Async.RunSynchronously