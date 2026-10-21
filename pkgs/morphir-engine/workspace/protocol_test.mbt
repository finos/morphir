// Upstream FINOS Morphir workspace discovery corpus, Apache-2.0.
// Source revision: 5c5307d89f34d876e8f1ebf561ec55efbadf9fa0.
// Generated from fixtures/upstream.json.

///|
test "root-adjacent-toml" {
  let request = @json.parse(
    "{\"protocolVersion\":\"0.1.0\",\"developmentRoot\":{\"entries\":{\"morphir.toml\":{\"kind\":\"file\",\"text\":\"[project]\\nname = \\\"layout/root-toml\\\"\\nversion = \\\"1.0.0\\\"\\nsource_directory = \\\"src\\\"\\n\"}}},\"morphirHome\":null,\"systemConfig\":null,\"environment\":{},\"cliOverlay\":{}}",
  )
  let expected = @json.parse(
    "{\"protocolVersion\":\"0.1.0\",\"configAnchor\":\"morphir.toml\",\"name\":null,\"state\":\"open\",\"projects\":[{\"name\":\"layout/root-toml\",\"version\":\"1.0.0\",\"relativePath\":\".\",\"configAnchor\":\"morphir.toml\",\"sourceDirectory\":\"src\",\"state\":\"unloaded\",\"diagnostics\":[]}],\"diagnostics\":[]}",
  )
  assert_eq(@workspace.discover_request(request).to_json(), expected)
}

///|
test "member-project-discovery" {
  let request = @json.parse(
    "{\"protocolVersion\":\"0.1.0\",\"developmentRoot\":{\"entries\":{\"morphir.toml\":{\"kind\":\"file\",\"text\":\"[workspace]\\nmembers = [\\\"packages/member\\\"]\\n\"},\"packages\":{\"kind\":\"directory\"},\"packages/member\":{\"kind\":\"directory\"},\"packages/member/morphir.toml\":{\"kind\":\"file\",\"text\":\"[project]\\nname = \\\"member/orders\\\"\\nversion = \\\"1.0.0\\\"\\nsource_directory = \\\"src\\\"\\n\"}}},\"morphirHome\":null,\"systemConfig\":null,\"environment\":{},\"cliOverlay\":{}}",
  )
  let expected = @json.parse(
    "{\"protocolVersion\":\"0.1.0\",\"configAnchor\":\"morphir.toml\",\"name\":null,\"state\":\"open\",\"projects\":[{\"name\":\"member/orders\",\"version\":\"1.0.0\",\"relativePath\":\"packages/member\",\"configAnchor\":\"packages/member/morphir.toml\",\"sourceDirectory\":\"src\",\"state\":\"unloaded\",\"diagnostics\":[]}],\"diagnostics\":[]}",
  )
  assert_eq(@workspace.discover_request(request).to_json(), expected)
}

///|
test "morphir-directory-toml" {
  let request = @json.parse(
    "{\"protocolVersion\":\"0.1.0\",\"developmentRoot\":{\"entries\":{\".morphir\":{\"kind\":\"directory\"},\".morphir/morphir.toml\":{\"kind\":\"file\",\"text\":\"[project]\\nname = \\\"layout/dot-morphir-toml\\\"\\nsource_directory = \\\"source\\\"\\n\"}}},\"morphirHome\":null,\"systemConfig\":null,\"environment\":{},\"cliOverlay\":{}}",
  )
  let expected = @json.parse(
    "{\"protocolVersion\":\"0.1.0\",\"configAnchor\":\".morphir/morphir.toml\",\"name\":null,\"state\":\"open\",\"projects\":[{\"name\":\"layout/dot-morphir-toml\",\"version\":null,\"relativePath\":\".\",\"configAnchor\":\".morphir/morphir.toml\",\"sourceDirectory\":\"source\",\"state\":\"unloaded\",\"diagnostics\":[]}],\"diagnostics\":[]}",
  )
  assert_eq(@workspace.discover_request(request).to_json(), expected)
}

///|
test "dot-config-toml" {
  let request = @json.parse(
    "{\"protocolVersion\":\"0.1.0\",\"developmentRoot\":{\"entries\":{\".config\":{\"kind\":\"directory\"},\".config/morphir\":{\"kind\":\"directory\"},\".config/morphir/config.toml\":{\"kind\":\"file\",\"text\":\"[project]\\nname = \\\"layout/dot-config-toml\\\"\\nsource_directory = \\\"src\\\"\\n\"}}},\"morphirHome\":null,\"systemConfig\":null,\"environment\":{},\"cliOverlay\":{}}",
  )
  let expected = @json.parse(
    "{\"protocolVersion\":\"0.1.0\",\"configAnchor\":\".config/morphir/config.toml\",\"name\":null,\"state\":\"open\",\"projects\":[{\"name\":\"layout/dot-config-toml\",\"version\":null,\"relativePath\":\".\",\"configAnchor\":\".config/morphir/config.toml\",\"sourceDirectory\":\"src\",\"state\":\"unloaded\",\"diagnostics\":[]}],\"diagnostics\":[]}",
  )
  assert_eq(@workspace.discover_request(request).to_json(), expected)
}

///|
test "excluded-member-omitted" {
  let request = @json.parse(
    "{\"protocolVersion\":\"0.1.0\",\"developmentRoot\":{\"entries\":{\"morphir.toml\":{\"kind\":\"file\",\"text\":\"[workspace]\\nmembers = [\\\"packages/*\\\"]\\nexclude = [\\\"packages/private\\\"]\\n\"},\"packages\":{\"kind\":\"directory\"},\"packages/private\":{\"kind\":\"directory\"},\"packages/private/morphir.toml\":{\"kind\":\"file\",\"text\":\"[project]\\nname = \\\"excluded/private\\\"\\nversion = \\\"1.0.0\\\"\\nsource_directory = \\\"src\\\"\\n\"},\"packages/public\":{\"kind\":\"directory\"},\"packages/public/morphir.toml\":{\"kind\":\"file\",\"text\":\"[project]\\nname = \\\"excluded/public\\\"\\nversion = \\\"1.0.0\\\"\\nsource_directory = \\\"src\\\"\\n\"}}},\"morphirHome\":null,\"systemConfig\":null,\"environment\":{},\"cliOverlay\":{}}",
  )
  let expected = @json.parse(
    "{\"protocolVersion\":\"0.1.0\",\"configAnchor\":\"morphir.toml\",\"name\":null,\"state\":\"open\",\"projects\":[{\"name\":\"excluded/public\",\"version\":\"1.0.0\",\"relativePath\":\"packages/public\",\"configAnchor\":\"packages/public/morphir.toml\",\"sourceDirectory\":\"src\",\"state\":\"unloaded\",\"diagnostics\":[]}],\"diagnostics\":[]}",
  )
  assert_eq(@workspace.discover_request(request).to_json(), expected)
}

///|
test "root-is-both-workspace-and-project" {
  let request = @json.parse(
    "{\"protocolVersion\":\"0.1.0\",\"developmentRoot\":{\"entries\":{\"morphir.toml\":{\"kind\":\"file\",\"text\":\"[workspace]\\nmembers = []\\ndefault_member = \\\".\\\"\\n\\n[project]\\nname = \\\"both/root\\\"\\nversion = \\\"7.0.0\\\"\\nsource_directory = \\\"root-src\\\"\\n\"}}},\"morphirHome\":null,\"systemConfig\":null,\"environment\":{},\"cliOverlay\":{}}",
  )
  let expected = @json.parse(
    "{\"protocolVersion\":\"0.1.0\",\"configAnchor\":\"morphir.toml\",\"name\":null,\"state\":\"open\",\"projects\":[{\"name\":\"both/root\",\"version\":\"7.0.0\",\"relativePath\":\".\",\"configAnchor\":\"morphir.toml\",\"sourceDirectory\":\"root-src\",\"state\":\"unloaded\",\"diagnostics\":[]}],\"diagnostics\":[]}",
  )
  assert_eq(@workspace.discover_request(request).to_json(), expected)
}

///|
test "root-user-project-and-workspace-do-not-flow-to-member" {
  let request = @json.parse(
    "{\"protocolVersion\":\"0.1.0\",\"developmentRoot\":{\"entries\":{\"morphir.toml\":{\"kind\":\"file\",\"text\":\"[workspace]\\nname = \\\"primary-workspace\\\"\\nmembers = [\\\"packages/member\\\"]\\n\\n[project]\\nname = \\\"root/primary\\\"\\nversion = \\\"1.0.0\\\"\\nsource_directory = \\\"root-primary-src\\\"\\n\\n[ir]\\nmode = \\\"root-primary\\\"\\n\"},\"morphir.user.toml\":{\"kind\":\"file\",\"text\":\"[workspace]\\nname = \\\"root-user-workspace\\\"\\n\\n[project]\\nname = \\\"root/user\\\"\\nversion = \\\"2.0.0\\\"\\nsource_directory = \\\"root-user-src\\\"\\n\\n[ir]\\nstrict_mode = true\\n\"},\"packages\":{\"kind\":\"directory\"},\"packages/member\":{\"kind\":\"directory\"},\"packages/member/morphir.toml\":{\"kind\":\"file\",\"text\":\"[project]\\nname = \\\"member/primary\\\"\\nversion = \\\"1.0.0\\\"\\nsource_directory = \\\"member-primary-src\\\"\\n\\n[ir]\\nformat_version = 3\\n\"},\"packages/member/morphir.user.toml\":{\"kind\":\"file\",\"text\":\"[project]\\nversion = \\\"3.0.0\\\"\\n\\n[ir]\\nmode = \\\"member-user\\\"\\n\"}}},\"morphirHome\":null,\"systemConfig\":null,\"environment\":{},\"cliOverlay\":{}}",
  )
  let expected = @json.parse(
    "{\"protocolVersion\":\"0.1.0\",\"configAnchor\":\"morphir.toml\",\"name\":\"root-user-workspace\",\"state\":\"open\",\"projects\":[{\"name\":\"root/user\",\"version\":\"2.0.0\",\"relativePath\":\".\",\"configAnchor\":\"morphir.toml\",\"sourceDirectory\":\"root-user-src\",\"state\":\"unloaded\",\"diagnostics\":[]},{\"name\":\"member/primary\",\"version\":\"3.0.0\",\"relativePath\":\"packages/member\",\"configAnchor\":\"packages/member/morphir.toml\",\"sourceDirectory\":\"member-primary-src\",\"state\":\"unloaded\",\"diagnostics\":[]}],\"diagnostics\":[]}",
  )
  assert_eq(@workspace.discover_request(request).to_json(), expected)
}
