///|
fn pin(
  name : String,
  alternate~ : Bool = false,
) -> PackagePin raise AssemblyError {
  PackagePin::new(
    name,
    if alternate {
      "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
    } else {
      "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    },
  )
}

///|
fn fixture(
  name : String,
  dependencies : Array[(String, String)],
) -> Package raise AssemblyError {
  Package::new(
    pin(name),
    dependencies.map(pair => Dependency::new(pair.0, pin(pair.1))),
  )
}

///|
fn names(value : Plan) -> Array[String] {
  value.packages().map(entry => entry.pin().name())
}

///|
fn[T] rejected(f : () -> T raise AssemblyError) -> AssemblyError raise {
  try f() |> ignore catch {
    error => return error
  }
  fail("Expected assembly refusal")
}

///|
test "deterministic full assembly order and shared transitive dependencies" {
  let sdk = fixture("morphir/sdk", [])
  let base = fixture("example/base", [("sdk", "morphir/sdk")])
  let library = fixture("example/library", [
    ("base", "example/base"),
    ("sdk", "morphir/sdk"),
  ])
  let main = fixture("example/main", [
    ("library", "example/library"),
    ("other_alias", "morphir/sdk"),
  ])
  let extra = fixture("example/extra", [])
  let first = plan(pin("example/main"), [main, library, sdk, base, extra])
  let second = plan(pin("example/main"), [extra, base, sdk, library, main])
  assert_eq(first, second)
  let sequence = names(first)
  let positions : Map[String, Int32] = Map([])
  for i in 0..<sequence.length() {
    positions[sequence[i]] = i
  }
  assert_eq(positions.length(), 5)
  assert_true(
    positions.get("morphir/sdk").unwrap() <
    positions.get("example/base").unwrap(),
  )
  assert_true(
    positions.get("example/base").unwrap() <
    positions.get("example/library").unwrap(),
  )
  assert_true(
    positions.get("example/library").unwrap() <
    positions.get("example/main").unwrap(),
  )
  assert_true(positions.contains("example/extra"))
  assert_eq(first.root(), pin("example/main"))
}

///|
test "aliases are local and input dependency order is normalized" {
  let a = Dependency::new("a", pin("deps/a"))
  let b = Dependency::new("b", pin("deps/b"))
  assert_eq(
    Package::new(pin("example/main"), [b, a]),
    Package::new(pin("example/main"), [a, b]),
  )
  assert_eq(a.import_name(), "a")
  assert_eq(a.target(), pin("deps/a"))
}

///|
test "packages and plans own their dependency snapshots" {
  let deps = [Dependency::new("dep", pin("deps/a"))]
  let main = Package::new(pin("example/main"), deps)
  deps.clear()
  main.dependencies().clear()
  let result = plan(pin("example/main"), [main, fixture("deps/a", [])])
  result.packages().clear()
  assert_eq(names(result), ["deps/a", "example/main"])
  assert_eq(main.dependencies().length(), 1)
}

///|
test "missing packages and exact pin mismatches name the referring package" {
  let main = fixture("example/main", [("dep", "deps/a")])
  match
    rejected(fn() raise AssemblyError { plan(pin("example/main"), [main]) }) {
    MissingPackage(referrer, dependency) => {
      assert_eq(referrer, DependencyOf(pin("example/main")))
      assert_eq(dependency, pin("deps/a"))
    }
    _ => fail("expected missing dependency")
  }
  let changed = Package::new(pin("deps/a", alternate=true), [])
  match
    rejected(fn() raise AssemblyError {
      plan(pin("example/main"), [main, changed])
    }) {
    RevisionMismatch(referrer, expected, actual) => {
      assert_eq(referrer, DependencyOf(pin("example/main")))
      assert_eq(expected.name(), "deps/a")
      assert_true(expected != actual)
    }
    _ => fail("expected incompatible pin")
  }
}

///|
test "unused supplied packages still receive dependency validation" {
  let main = fixture("example/main", [])
  let unused = fixture("example/unused", [("missing", "deps/missing")])
  match
    rejected(fn() raise AssemblyError {
      plan(pin("example/main"), [main, unused])
    }) {
    MissingPackage(referrer, _) =>
      assert_eq(referrer, DependencyOf(pin("example/unused")))
    _ => fail("expected unused supplied dependency refusal")
  }
}

///|
test "cycles retain their path" {
  let a = fixture("example/a", [("b", "example/b")])
  let b = fixture("example/b", [("c", "example/c")])
  let c = fixture("example/c", [("a", "example/a")])
  match
    rejected(fn() raise AssemblyError { plan(pin("example/a"), [c, b, a]) }) {
    DependencyCycle(path) =>
      assert_eq(path.map(p => p.name()), [
        "example/a", "example/b", "example/c", "example/a",
      ])
    _ => fail("expected cycle path")
  }
  let self = fixture("example/self", [("self", "example/self")])
  match
    rejected(fn() raise AssemblyError { plan(pin("example/self"), [self]) }) {
    DependencyCycle(path) =>
      assert_eq(path.map(p => p.name()), ["example/self", "example/self"])
    _ => fail("expected self cycle")
  }
}

///|
test "duplicates and missing or mismatched roots refuse" {
  let main = fixture("example/main", [])
  match
    rejected(fn() raise AssemblyError {
      plan(pin("example/main"), [main, main])
    }) {
    DuplicatePackage(name) => assert_eq(name, "example/main")
    _ => fail("expected duplicate package")
  }
  match rejected(fn() raise AssemblyError { plan(pin("example/main"), []) }) {
    MissingPackage(referrer, _) => assert_eq(referrer, SelectedRoot)
    _ => fail("expected missing root")
  }
  match
    rejected(fn() raise AssemblyError {
      plan(pin("example/main", alternate=true), [main])
    }) {
    RevisionMismatch(referrer, _, _) => assert_eq(referrer, SelectedRoot)
    _ => fail("expected mismatched root")
  }
  let dep = Dependency::new("dep", pin("deps/a"))
  match
    rejected(fn() raise AssemblyError {
      Package::new(pin("example/main"), [dep, dep])
    }) {
    DuplicateAlias(name, import_name) => {
      assert_eq(name, pin("example/main"))
      assert_eq(import_name, "dep")
    }
    _ => fail("expected duplicate alias")
  }
}

///|
test "pins and aliases reject malformed input and preserve exact spelling" {
  for name in ["", "/root", "a//b", "a/../b", "a/b/", "a b", "a\u0000b"] {
    match rejected(fn() raise AssemblyError { pin(name) }) {
      InvalidPackageName(_) => ()
      _ => fail("expected invalid package name")
    }
  }
  for
    digest in [
      "", "sha256:abc", "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
      "gggggggggggggggggggggggggggggggggggggggggggggggggggggggggggggggg",
    ] {
    match
      rejected(fn() raise AssemblyError {
        PackagePin::new("example/main", digest)
      }) {
      InvalidDigest(_) => ()
      _ => fail("expected invalid digest")
    }
  }
  for import_name in ["", "0dep", "a-b", "a/b", "a b"] {
    match
      rejected(fn() raise AssemblyError {
        Dependency::new(import_name, pin("deps/a"))
      }) {
      InvalidAlias(_) => ()
      _ => fail("expected invalid alias")
    }
  }
  assert_eq(pin("Example/pkg-name_2").name(), "Example/pkg-name_2")
  assert_eq(pin("Example/pkg-name_2").sha256().length(), 64)
}

///|
test "deep dependency graphs use an explicit traversal stack" {
  let count = 4000
  let packages = Array::makei(count, i => {
    let name = "deep/p" + i.to_string()
    fixture(
      name,
      if i + 1 < count {
        [("next", "deep/p" + (i + 1).to_string())]
      } else {
        []
      },
    )
  })
  let ordered = plan(pin("deep/p0"), packages).packages()
  assert_eq(ordered.length(), count)
  assert_eq(ordered[0].pin().name(), "deep/p3999")
  assert_eq(ordered[count - 1].pin().name(), "deep/p0")
}
