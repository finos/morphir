namespace Morphir.Live.Components.Layout

open Microsoft.AspNetCore.Components
open MudBlazor
open Fun.Blazor

type MainLayout() as this =
    inherit LayoutComponentBase()

    let mutable isDrawerOpen = true

    let content =
        html.fragment [|
            MudThemeProvider'.create ()
            MudLayout'() {
                MudAppBar'() {
                    // This will not work, because the layout is not all in server/client interactive mode,
                    // some pages are SSR, so by default the whole app is static and cannot interact.
                    // MudIconButton'() {
                    //     Icon Icons.Material.Filled.Menu
                    //     Color Color.Inherit
                    //     Edge Edge.Start
                    //     OnClick(fun _ -> isDrawerOpen <- not isDrawerOpen)
                    // }
                    
                    MudText'() {
                        Typo Typo.h5
                        "Morphir"
                    }
                    //SectionOutlet'() { SectionName "header" }
                }
                MudDrawer'() {
                    ClipMode DrawerClipMode.Always
                    Open isDrawerOpen
                    //OpenChanged(fun x -> isDrawerOpen <- x)
                    NavMenu.Create()
                }
                MudMainContent'() { MudContainer'() { this.Body } }
            }
        |]

    override _.BuildRenderTree(builder) = content.Invoke(this, builder, 0) |> ignore
