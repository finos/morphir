# Log

## 2026-09-24

* **Creation**: Added [Extensions make capability claims](/decisions/0007-extensions-make-capability-claims.md), renaming capability statements to capability claim sets.
* **Update**: Renamed the design note to [Capability claims across the extension lifecycle](/design/capability-claims.md) (was `design/capability-statements.md`) and moved its vocabulary and examples to capability claims and the draft.2 formats, per decision 0007. Its status now says the host side shipped in `0.4.0-beta.5` and `0.4.0-beta.6`, and the section on work in flight is replaced by the outcomes: the bootstrap host release, the three retired transitional mechanisms, the Elm workspace discovery release and the remaining extension-side work (beads epic `morphir-o7m2`).

## 2026-09-23

* **Creation**: Added [Elm providers normalize explicit package names](/decisions/0005-elm-providers-normalize-explicit-package-names.md).
* **Creation**: Added [The describe fallback reports only what a session reports](/decisions/0006-the-describe-fallback-reports-only-what-a-session-reports.md), refining decision 9 of 0004.
* **Update**: [Capability statements across the extension lifecycle](/design/capability-claims.md) names the `-32014` (not initialized) refusal.

## 2026-09-22

* **Creation**: Added [Capability statements across the extension lifecycle](/design/capability-claims.md), the narrative home for capability statements, from finos/morphir#921.
* **Creation**: Added [The guest authors its capability statement](/decisions/0003-the-guest-authors-its-capability-statement.md).
* **Creation**: Added [Readers ignore unknown members unless critical](/decisions/0004-readers-ignore-unknown-members-unless-critical.md).
* **Update**: [Elm extension delivery](/design/elm-extension-delivery.md) now points its process-bundle publication gap to the capability statements design and decision 0003.
* **Update**: The capability statement, the release descriptor and the workspace discovery protocol use SemVer versions (`0.1.0-draft.1`, `2.0.0-draft.1`), per the morphir-cli decision that makes SemVer the default contract versioning scheme; decision 0004's range rule is restated in those terms.

## 2026-09-19

* **Creation**: Added [Extensions declare IR capability sets](/decisions/0002-extension-capability-sets.md).

## 2026-09-18

* **Creation**: Bundle created.
* **Creation**: Added [Two Elm frontend providers](/decisions/0001-two-elm-frontend-providers.md).
* **Creation**: Added [A JavaScript runtime mode for extensions: exploration](/design/js-extension-runtime-exploration.md).
* **Creation**: Added [Elm extension delivery](/design/elm-extension-delivery.md).
