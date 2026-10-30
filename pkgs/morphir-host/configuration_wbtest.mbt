///|
priv suberror LockedConfigurationEntry

///|
test "configuration discovery retains locked sibling entries without failing the listing" {
  let entries = configuration_entries(
    "C:/",
    ["DumpStack.log.tmp", "morphir.toml", "app"],
    path => {
      if path.has_suffix("DumpStack.log.tmp") {
        raise LockedConfigurationEntry
      }
      if path.has_suffix("morphir.toml") {
        1
      } else {
        2
      }
    },
  )
  assert_eq(entries.map(entry => entry.kind), [
    @lander_config.Inaccessible,
    @lander_config.File,
    @lander_config.Directory,
  ])
  let tree = @lander_config.FileTree::new().with_listing(
    @lander_config.FileTreePath::parse("/"),
    entries,
  )
  assert_true(
    tree.is_file(@lander_config.FileTreePath::parse("/DumpStack.log.tmp"))
    is Unknown,
  )
  assert_true(
    tree.is_file(@lander_config.FileTreePath::parse("/morphir.toml"))
    is Found(true),
  )
}
