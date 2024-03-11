#nowarn "0020"

open System
open MudBlazor.Services
open Microsoft.AspNetCore.Components.WebAssembly.Hosting

let builder = WebAssemblyHostBuilder.CreateDefault(Environment.GetCommandLineArgs())

builder.Services.AddMudServices()

builder.Build().RunAsync()
