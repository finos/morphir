namespace Morphir.Live.Components

open Fun.Blazor
open Microsoft.AspNetCore.Components.Web


type App() =
    inherit FunComponent()

    override _.Render() =
        html.fragment [|
            doctype "html"
            html' {
                lang "EN"
                head.create [|
                    baseUrl "/"
                    meta { charset "utf-8" }
                    meta {
                        name "viewport"
                        content "width=device-width, initial-scale=1.0"
                    }
                    link {
                        rel "icon"
                        type' "image/png"
                        href "favicon.png"
                    }
                    styleElt {
                        ruleset ".active" {
                            color "green"
                            fontWeightBold
                        }
                    }
                    stylesheet "https://fonts.googleapis.com/css?family=Roboto:300,400,500,700&display=swap"
                    stylesheet "_content/MudBlazor/MudBlazor.min.css"
                    HeadOutlet'.create ()
                |]
                body {
                    html.blazor<Routes> ()
                    script { src "_framework/blazor.web.js" }
                    script { src "_content/MudBlazor/MudBlazor.min.js" }
                }
            }
        |]
