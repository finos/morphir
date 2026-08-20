# Security Policy

Morphir supports responsible disclosure of security vulnerabilities and adheres to the [FINOS Security Vulnerabilities Responsible Disclosure Policy](https://community.finos.org/docs/governance/software-projects/cve-responsible-disclosure).

If you believe you have found a security vulnerability in Morphir, we encourage and appreciate your report. Please report it privately using one of the methods below — **do not** open a public GitHub issue, post to the mailing list, or otherwise disclose it publicly until it has been formally announced.

## Reporting a Vulnerability

- **GitHub private vulnerability reporting (preferred).** Use the ["Report a vulnerability"](../../security/advisories/new) button under this repository's **Security** tab. This opens a private advisory and a confidential communication channel with the maintainers.
- **Email.** If you are unable to use GitHub's private reporting, email [morphir-maintainers-private@lists.finos.org](mailto:morphir-maintainers-private@lists.finos.org) and [security@finos.org](mailto:security@finos.org) with a description of the issue.

A useful report includes the affected repository and version, a description of the vulnerability and its impact, and steps to reproduce it where possible.

## Our Commitment

- We will **acknowledge receipt of your report within 5 business days**.
- We will provide an initial assessment — whether we can reproduce the issue and consider it a vulnerability — **within 10 business days** of acknowledgement.
- We will keep you informed of progress as we investigate and develop a fix, and will coordinate disclosure timing with you.
- We will credit you in the published advisory unless you ask us not to.

FINOS does not operate a bug bounty program, and no monetary reward is offered for vulnerability reports.

## Vulnerability Handling Process

1. You report the vulnerability privately using one of the methods above.
2. The maintainers acknowledge receipt, triage the report, and — if confirmed — work with you to investigate and develop a fix.
3. A patched release is prepared and published.
4. The vulnerability is publicly disclosed as a [GitHub Security Advisory](../../security/advisories) on the affected repository, and announced in accordance with the FINOS Security Vulnerabilities Responsible Disclosure Policy.

No information about a vulnerability is made public — including in issues, pull requests, or commit messages — before it is formally announced.

## Scope

This policy applies to Morphir repositories in the [FINOS GitHub organization](https://github.com/finos?q=morphir), including the tooling, language bindings, and reference implementations maintained by the Morphir project.

Security fixes are applied to the latest release of each actively maintained repository. Repositories that are no longer actively maintained are archived; archived repositories do not receive security fixes, and their archived status is visible on the repository page.

## Reporting Vulnerabilities in Dependencies

If the vulnerability is in a third-party dependency rather than in Morphir code, please report it to that project first, following its own disclosure policy. You are still welcome to notify us privately so that we can track the exposure and plan an upgrade.

---

Thank you for helping keep Morphir and its users secure.
