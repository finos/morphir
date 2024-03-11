namespace Morphir.Live.Client.Pages

open Microsoft.AspNetCore.Components
open Microsoft.AspNetCore.Components.Web
open MudBlazor
open Fun.Blazor

[<Route "/counter">]
[<FunInteractiveAuto>]
type Counter() as this =
    inherit FunComponent()

    let mutable count = 0

    [<Inject>]
    member val Snackbar = Unchecked.defaultof<ISnackbar> with get, set

    override _.Render() =
        html.fragment [|
            // Because the whole app is static, so for the dynamic part like snackbar, they should be rendered together with dynamic component
            MudSnackbarProvider'.create ()
            PageTitle'() { "Counter" }
            SectionContent'() {
                SectionName "header"
                h1 { "Counter" }
            }
            p { $"Current count: {count}" }
            MudButton'() {
                Color Color.Success
                OnClick(fun _ -> 
                    count <- count + 1
                    this.Snackbar.Add($"Count = {count}", severity = Severity.Success) |> ignore
                )
                "Click me"
            }
        |]
