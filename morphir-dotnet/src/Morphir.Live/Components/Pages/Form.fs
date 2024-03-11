namespace Morphir.Live.Components.Pages
open System
open System.Threading.Tasks
open Microsoft.AspNetCore.Components
open Microsoft.AspNetCore.Components.Web
open Microsoft.AspNetCore.Components.Forms
open MudBlazor
open Fun.Blazor

[<Route "/form">]
[<StreamRendering>]
type Form() as this =
    inherit FunComponent()

    let mutable isSubmitting = false

    [<SupplyParameterFromForm>]
    member val Query: string = null with get, set

    member _.Submit() = task {
        isSubmitting <- true
        this.StateHasChanged()

        do! Task.Delay 1000
        isSubmitting <- false
        this.StateHasChanged()
    }

    member _.FormView = form {
        onsubmit (ignore >> this.Submit)
        method "post"
        dataEnhance
        formName "person-info"
        childContent [|
            html.blazor<AntiforgeryToken> ()
            MudTextField'() {
                "name", nameof this.Query
                Value this.Query
                Error(String.IsNullOrEmpty this.Query || this.Query.Length > 5)
                ErrorText $"{nameof this.Query} is not valid"
            }
            MudButton'() {
                ButtonType ButtonType.Submit
                "Submit"
            }
        |]
    }

    override _.Render() =
        html.fragment [|
            PageTitle'() { "Form demo" }
            SectionContent'() {
                SectionName "header"
                h1 { "Form demo" }
            }
            div {
                style { height "100vh" }
                MudLink'() {
                    Href "form?#person-info"
                    "check the form"
                }
            }
            h2 {
                id "person-info"
                "person info"
            }
            this.FormView
            region { if isSubmitting then MudProgressLinear'() { Indeterminate true } }
            div { style { height "100vh" } }
        |]
