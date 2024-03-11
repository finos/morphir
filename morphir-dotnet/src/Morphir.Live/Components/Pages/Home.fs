namespace Morphir.Live.Components.Pages

open System
open System.Threading.Tasks
open Microsoft.AspNetCore.Components
open Microsoft.AspNetCore.Components.Web
open MudBlazor
open Fun.Blazor

[<Route "/">]
[<StreamRendering>]
type Home() as this =
    inherit FunComponent()

    let mutable items = []

    [<SupplyParameterFromQuery>]
    member val query = Nullable<int>() with get, set

    member _.FilteredItems =
        if this.query.HasValue then
            items |> Seq.filter (fun x -> x > this.query.Value)
        else
            items

    member _.MainContent =
        html.fragment [|
            div {
                a {
                    style { color (if this.query.HasValue then "hotpink" else "grey") }
                    href "?query=3"
                    "filter: bigger than 3"
                }
            }
            ul {
                region {
                    for i in this.FilteredItems do
                        li {
                            style { color "green" }
                            $"item {i}"
                        }
                }
            }
        |]

    override _.OnInitializedAsync() = task {
        do! Task.Delay 2000
        items <- [ 1..5 ]
        this.StateHasChanged()

        do! Task.Delay 1000
        items <- [ 1..10 ]
        this.StateHasChanged()
    }

    override _.Render() =
        html.fragment [|
            PageTitle'() { "Home" }
            SectionContent'() {
                SectionName "header"
                h1 { "Home" }
            }
            region {
                if items.IsEmpty then
                    MudProgressLinear'() { Indeterminate true }
                else
                    this.MainContent
            }
        |]
