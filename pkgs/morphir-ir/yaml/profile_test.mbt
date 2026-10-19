// Expectations frozen independently in headless-parity/v1/yaml/cases.json
// SHA256 9a3c08d33ffe0be59fd745289e4f037a59f48814b9ba7cdae9f926431545b744.

///|
test "independent YAML readable" {
  assert_eq(
    @codec.to_json(
      @yaml.read(
        "formatVersion: 4\ndistribution:\n  Library:\n    packageName: parity\n    dependencies: {}\n    def: {modules: {}}\n",
      ),
    ).stringify(),
    "{\"formatVersion\":4,\"distribution\":{\"Library\":{\"packageName\":\"parity\",\"dependencies\":{},\"def\":{\"modules\":{}}}}}",
  )
}

///|
test "independent YAML structural" {
  assert_eq(
    @codec.to_json(
      @yaml.read(
        "formatVersion: 4\ndistribution:\n  Library:\n    packageName: [[parity]]\n    dependencies: {}\n    def: {modules: {}}\n",
      ),
    ).stringify(),
    "{\"formatVersion\":4,\"distribution\":{\"Library\":{\"packageName\":\"parity\",\"dependencies\":{},\"def\":{\"modules\":{}}}}}",
  )
}

///|
test "independent YAML v1-explicit-migration" {
  assert_eq(
    @codec.to_json(
      @yaml.read(
        "formatVersion: 1\ndistribution: [\"library\", [[\"parity\"]], [], {modules: []}]\n",
      ),
    ).stringify(),
    "{\"formatVersion\":4,\"distribution\":{\"Library\":{\"packageName\":\"parity\",\"dependencies\":{},\"def\":{\"modules\":{}}}}}",
  )
}

///|
test "independent YAML v2-explicit-migration" {
  assert_eq(
    @codec.to_json(
      @yaml.read(
        "formatVersion: 2\ndistribution: [\"Library\", [[\"parity\"]], [], {modules: []}]\n",
      ),
    ).stringify(),
    "{\"formatVersion\":4,\"distribution\":{\"Library\":{\"packageName\":\"parity\",\"dependencies\":{},\"def\":{\"modules\":{}}}}}",
  )
}

///|
test "independent YAML v3-explicit-migration" {
  assert_eq(
    @codec.to_json(
      @yaml.read(
        "formatVersion: 3\ndistribution: [\"Library\", [[\"parity\"]], [], {modules: []}]\n",
      ),
    ).stringify(),
    "{\"formatVersion\":4,\"distribution\":{\"Library\":{\"packageName\":\"parity\",\"dependencies\":{},\"def\":{\"modules\":{}}}}}",
  )
}

///|
test "independent YAML bom-crlf-comments" {
  assert_eq(
    @codec.to_json(
      @yaml.read(
        "﻿# retained\r\nformatVersion: '4.0.0' # version\r\ndistribution:\r\n  Library:\r\n    packageName: parity\r\n    dependencies: {}\r\n    def: {modules: {}}\r\n",
      ),
    ).stringify(),
    "{\"formatVersion\":4,\"distribution\":{\"Library\":{\"packageName\":\"parity\",\"dependencies\":{},\"def\":{\"modules\":{}}}}}",
  )
}

///|
test "independent YAML exact-integer" {
  assert_eq(
    @yaml.parse("value: 9007199254740993\n").stringify(),
    "{\"value\":9007199254740993}",
  )
}

///|
test "independent YAML exact-decimal" {
  assert_eq(
    @yaml.parse("value: 123.4500\n").stringify(),
    "{\"value\":123.4500}",
  )
}

///|
test "independent YAML date-looking" {
  assert_eq(
    @yaml.parse("value: 2026-01-15\n").stringify(),
    "{\"value\":\"2026-01-15\"}",
  )
}

///|
test "independent YAML multiline" {
  assert_eq(
    @yaml.parse("value: |\n  first\n  second\n\n").stringify(),
    "{\"value\":\"first\\nsecond\\n\"}",
  )
}

///|
test "independent YAML duplicate" {
  let code = try {
    ignore(@yaml.parse("formatVersion: 4\nformatVersion: 4\n"))
    "accepted"
  } catch {
    @wire.Invalid(code, _) => code
  }
  assert_eq(code, "duplicate_member")
}

///|
test "independent YAML tag" {
  let code = try {
    ignore(@yaml.parse("value: !!int 42\n"))
    "accepted"
  } catch {
    @wire.Invalid(code, _) => code
  }
  assert_eq(code, "unsupported_yaml_feature")
}

///|
test "independent YAML anchor" {
  let code = try {
    ignore(@yaml.parse("value: &x 42\n"))
    "accepted"
  } catch {
    @wire.Invalid(code, _) => code
  }
  assert_eq(code, "unsupported_yaml_feature")
}

///|
test "independent YAML alias" {
  let code = try {
    ignore(@yaml.parse("value: *x\n"))
    "accepted"
  } catch {
    @wire.Invalid(code, _) => code
  }
  assert_eq(code, "unsupported_yaml_feature")
}

///|
test "independent YAML merge" {
  let code = try {
    ignore(@yaml.parse("value: {<<: {a: 1}}\n"))
    "accepted"
  } catch {
    @wire.Invalid(code, _) => code
  }
  assert_eq(code, "unsupported_yaml_feature")
}

///|
test "independent YAML directive" {
  let code = try {
    ignore(@yaml.parse("%YAML 1.2\n---\nvalue: 1\n"))
    "accepted"
  } catch {
    @wire.Invalid(code, _) => code
  }
  assert_eq(code, "unsupported_yaml_feature")
}

///|
test "independent YAML multiple-documents" {
  let code = try {
    ignore(@yaml.parse("value: 1\n---\nvalue: 2\n"))
    "accepted"
  } catch {
    @wire.Invalid(code, _) => code
  }
  assert_eq(code, "invalid_yaml")
}

///|
test "independent YAML nonfinite" {
  let code = try {
    ignore(@yaml.parse("value: .inf\n"))
    "accepted"
  } catch {
    @wire.Invalid(code, _) => code
  }
  assert_eq(code, "invalid_literal")
}

///|
test "independent YAML leading-zero" {
  let code = try {
    ignore(@yaml.parse("value: 01\n"))
    "accepted"
  } catch {
    @wire.Invalid(code, _) => code
  }
  assert_eq(code, "invalid_literal")
}

///|
test "independent YAML nonstring-key" {
  let code = try {
    ignore(@yaml.parse("1: value\n"))
    "accepted"
  } catch {
    @wire.Invalid(code, _) => code
  }
  assert_eq(code, "invalid_type")
}

///|
test "independent YAML sequence-root" {
  let code = try {
    ignore(@yaml.parse("[1, 2]\n"))
    "accepted"
  } catch {
    @wire.Invalid(code, _) => code
  }
  assert_eq(code, "invalid_type")
}
