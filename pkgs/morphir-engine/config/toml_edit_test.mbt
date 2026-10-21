///|
/// Compare the exact resulting text and its independently parsed config values.
fn edited(actual : @edit.Document, expected : String) -> Unit raise {
  assert_eq(actual.encode(), expected)
  assert_true(
    @config.parse(actual.encode()).value == @config.parse(expected).value,
  )
}

///|
test "tier 1 edits agree with the existing config parser" {
  let source = "# retained\n[workspace]\nmembers = ['one'] # members\n[project]\nname='Old'\noptions={ enabled=true, count=1 }\n"
  let doc = @edit.parse(source)
  edited(
    doc.set(["project", "name"], "'New'"),
    source.replace(old="'Old'", new="'New'"),
  )
  edited(
    doc.set(["project", "profile"], "'stable'"),
    source + "profile = 'stable'\n",
  )
  edited(
    doc.remove(["project", "name"]),
    source.replace(old="name='Old'", new=""),
  )
  edited(
    doc.append(["workspace", "members"], "'two'"),
    source.replace(old="['one']", new="['one','two']"),
  )
  edited(
    doc.remove_item(["workspace", "members"], 0),
    source.replace(old="['one']", new="[]"),
  )
  edited(
    doc.set(["project", "options", "count"], "2"),
    source.replace(old="count=1", new="count=2"),
  )
  edited(
    doc.set(["project", "options", "target"], "'moonbit'"),
    source.replace(old="count=1", new="count=1, target = 'moonbit'"),
  )
  edited(
    doc.remove(["project", "options", "enabled"]),
    source.replace(old="enabled=true,", new=""),
  )
  edited(
    doc.add_table(["extension", "quoted.key"]),
    source + "[extension.\"quoted.key\"]\n",
  )
  edited(
    doc.remove_table(["project"]),
    "# retained\n[workspace]\nmembers = ['one'] # members\n\n\n\n",
  )
  let implicit = @edit.parse("[a.b]\nx=1\n")
  edited(implicit.set(["a", "y"], "2"), "[a.b]\nx=1\n[a]\ny = 2\n")
}

///|
test "workspace configuration edits preserve every unrelated byte through a sequence" {
  let source = "# workspace config\r\n[workspace]\r\nmembers=[\r\n 'one', # the first\r\n]\r\n[project]\r\nname = 'Root' # root\r\n"
  let first = @edit.parse_bytes(
    b"# workspace config\r\n[workspace]\r\nmembers=[\r\n 'one', # the first\r\n]\r\n[project]\r\nname = 'Root' # root\r\n",
  )
  let added = first.append(["workspace", "members"], "'two'")
  edited(added, source.replace(old="\r\n]\r\n", new="\r\n'two']\r\n"))
  assert_eq(@config.parse(added.encode()).strings("workspace.members"), [
    "one", "two",
  ])
  let removed = added.remove_item(["workspace", "members"], 0)
  edited(
    removed,
    source
    .replace(old="'one',", new="")
    .replace(old="\r\n]\r\n", new="\r\n'two']\r\n"),
  )
  assert_eq(@config.parse(removed.encode()).strings("workspace.members"), [
    "two",
  ])
  assert_eq(first.encode(), source)
}

///|
test "dotted configuration edits keep dotted layout and agree with semantic reads" {
  let source = "# project\nproject.name = 'Shop' # name\nfrontend.language='elm'\nfrontend.profile='stable'\n[extension]\noptions = { nested.key = 1, sibling = 2 }\n"
  let doc = @edit.parse(source)
  edited(
    doc.set(["frontend", "language"], "'moonbit'"),
    source.replace(old="'elm'", new="'moonbit'"),
  )
  let added = doc.set(["frontend", "provider"], "'moonbit'")
  edited(
    added,
    source.replace(
      old="frontend.profile='stable'\n",
      new="frontend.profile='stable'\nfrontend.provider = 'moonbit'\n",
    ),
  )
  assert_eq(
    @config.parse(added.encode()).text("frontend.provider", ""),
    "moonbit",
  )
  edited(
    doc.remove(["frontend", "profile"]),
    source.replace(old="frontend.profile='stable'", new=""),
  )
}

///|
test "indexed array-of-tables edits agree with independent semantic configuration reads" {
  let source = "[project]\nname='Shop'\n[[extension.targets]]\nname='One'\n[extension.targets.options]\nx=1\n[[extension.targets]]\nname='Two'\n[other]\ny=3\n"
  let doc = @edit.parse(source)
  edited(
    doc.element(["extension", "targets"], 1).set(["name"], "'Second'"),
    source.replace(old="'Two'", new="'Second'"),
  )
  edited(
    doc.append_table(["extension", "targets"], [(["name"], "'Three'")]),
    source.replace(
      old="[other]",
      new="[[extension.targets]]\nname = 'Three'\n[other]",
    ),
  )
  edited(
    doc.element(["extension", "targets"], 0).delete(),
    "[project]\nname='Shop'\n[[extension.targets]]\nname='Two'\n[other]\ny=3\n",
  )
}
