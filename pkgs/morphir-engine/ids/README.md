# finos/morphir-engine/ids

Domain types for source languages, providers, profiles, backends, files and names. Today `morphir.json`
discovery and the package name and exposed modules of `plan` parse text into them; the other entry points (CLI
flags, TOML) follow with bead `morphir-ukvn.5.32`. Only the wire carries `String`. Each type wraps a `String`,
has `T::parse(String) -> T raise @config.Invalid` and `Show`.

| Type | Rule | Error prefix |
| --- | --- | --- |
| `LanguageId` | lowercase letter, then lowercase letters, digits and `-`; at most 64 characters | `frontend.invalid_language` |
| `ProfileId` | same as `LanguageId` | `frontend.invalid_profile` |
| `BackendId` | same as `LanguageId` | `frontend.invalid_backend` |
| `ProviderId` | non-empty, at most 256 characters, no control characters | `frontend.invalid_provider` |
| `FileExtension` | starts with `.`, has more than the dot, no `/`, `\`, `:` or control characters | `frontend.invalid_extensions` |
| `SourcePath` | relative, `/` separators, no empty, `.` or `..` part, no `\`, `:` or control characters | `frontend.invalid_source_path` |
| `SourceModuleName` | bounded identifier with no space, `/` or `\`; keeps the source syntax (`Sub.Util`) | `frontend.invalid_module` |
| `SourcePackageName` | bounded identifier that `canonical_path` converts; keeps its spelling | `frontend.invalid_package` |

`SourcePackageName::to_path` gives the canonical `@ir.Path`. `canonical_path` converts conventional spelling:
`My.Pkg` and `my/pkg` both give `my/pkg`.

```moonbit
let elm = "elm" |> @ids.LanguageId::parse
```
