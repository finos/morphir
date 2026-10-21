///|
test "the theme toggle cycles System, Light, Dark and back to System" {
  @expect.expect_all(s => {
    s.expect(@settings.ThemePreference::System.next()).to_equal(Light)
    s.expect(@settings.ThemePreference::Light.next()).to_equal(Dark)
    s.expect(@settings.ThemePreference::Dark.next()).to_equal(System)
  })
}

///|
test "System follows the system appearance; Light and Dark do not" {
  @expect.expect_all(s => {
    s
    .expect(@settings.ThemePreference::System.resolve(system=Dark))
    .to_equal(Dark)
    s
    .expect(@settings.ThemePreference::System.resolve(system=Light))
    .to_equal(Light)
    s
    .expect(@settings.ThemePreference::Light.resolve(system=Dark))
    .to_equal(Light)
    s
    .expect(@settings.ThemePreference::Dark.resolve(system=Light))
    .to_equal(Dark)
  })
}

///|
test "only Light and Dark set the data-theme attribute" {
  @expect.expect_all(s => {
    s.expect(@settings.ThemePreference::System.data_theme()).to_equal(None)
    s
    .expect(@settings.ThemePreference::Light.data_theme())
    .to_equal(Some("light"))
    s
    .expect(@settings.ThemePreference::Dark.data_theme())
    .to_equal(Some("dark"))
  })
}

///|
test "settings round-trip through their saved text" {
  @expect.expect_all(s => {
    for theme in @settings.themes {
      for workspace_sidebar in [@settings.WorkspaceSidebar::Collapsed, Expanded] {
        let settings : @settings.Settings = {
          theme,
          workspace_sidebar,
          files_view: Projects,
          editor_layout: if theme is Dark {
            Tabs
          } else {
            SideBySide
          },
        }
        s
        .expect(@settings.Settings::decode(settings.encode()), label=theme.id())
        .to_equal(settings)
      }
    }
    s
    .expect(
      (
        {
          theme: Dark,
          workspace_sidebar: Collapsed,
          files_view: Projects,
          editor_layout: SideBySide,
        } : @settings.Settings).encode(),
    )
    .to_equal("{\"theme\":\"dark\"}")
    s
    .expect(
      (
        {
          theme: Light,
          workspace_sidebar: Expanded,
          files_view: Projects,
          editor_layout: SideBySide,
        } : @settings.Settings).encode(),
    )
    .to_equal("{\"theme\":\"light\",\"workspaceSidebar\":\"expanded\"}")
  })
}

///|
/// Saved text and the theme it gives. The head script of `index.html` must give the same `data-theme` for each;
/// `scripts/theme-head.test.ts` checks it against the same cases.
let saved_cases : Array[(String, @settings.ThemePreference)] = [
  ("", System),
  ("{\"theme\":\"light\"}", Light),
  ("{\"theme\":\"dark\"}", Dark),
  ("{\"theme\":\"system\"}", System),
  ("{\"theme\":\"Dark\"}", System),
  ("{\"theme\":\"sepia\"}", System),
  ("{\"theme\":1}", System),
  ("{}", System),
  ("[\"dark\"]", System),
  ("\"dark\"", System),
  ("{\"theme\":", System),
  ("not json", System),
]

///|
test "missing, unreadable and unknown saved values give System" {
  @expect.expect_all(s => {
    for case in saved_cases {
      let (text, theme) = case
      s
      .expect(@settings.Settings::decode(text).theme, label=text)
      .to_equal(theme)
    }
  })
}

///|
test "each theme has a label and a stored spelling that parses back" {
  @expect.expect_all(s => {
    s
    .expect(@settings.themes.map(theme => theme.label()))
    .to_equal(["System", "Light", "Dark"])
    for theme in @settings.themes {
      s
      .expect(@settings.ThemePreference::parse(theme.id()), label=theme.id())
      .to_equal(Some(theme))
    }
    s.expect(@settings.ThemePreference::parse("auto")).to_equal(None)
  })
}

///|
test "a missing or unknown workspace sidebar value is collapsed" {
  @expect.expect_all(s => {
    for
      text in [
        "", "{}", "{\"workspaceSidebar\":\"Expanded\"}", "{\"workspaceSidebar\":true}",
        "{\"theme\":\"dark\",\"workspaceSidebar\":\"wide\"}",
      ] {
      s
      .expect(@settings.Settings::decode(text).workspace_sidebar, label=text)
      .to_equal(Collapsed)
    }
    s
    .expect(@settings.Settings::decode("{\"workspaceSidebar\":\"expanded\"}"))
    .to_equal({
      theme: System,
      workspace_sidebar: Expanded,
      files_view: Projects,
      editor_layout: SideBySide,
    })
    s.expect(@settings.WorkspaceSidebar::Collapsed.toggle()).to_equal(Expanded)
    s.expect(@settings.WorkspaceSidebar::Expanded.toggle()).to_equal(Collapsed)
  })
}

///|
test "the editor layout is side by side unless tabs were saved" {
  @expect.expect_all(s => {
    for
      text in ["", "{}", "{\"editorLayout\":\"Tabs\"}", "{\"editorLayout\":1}"] {
      s
      .expect(@settings.Settings::decode(text).editor_layout, label=text)
      .to_equal(SideBySide)
    }
    let tabs = @settings.Settings::decode(
      "{\"theme\":\"dark\",\"editorLayout\":\"tabs\"}",
    )
    s.expect(tabs.editor_layout, label="tabs").to_equal(Tabs)
    s
    .expect(tabs.encode(), label="saved")
    .to_equal("{\"theme\":\"dark\",\"editorLayout\":\"tabs\"}")
    s
    .expect(@settings.editor_layouts.map(layout => layout.label()))
    .to_equal(["Side by side", "Tabs"])
  })
}
