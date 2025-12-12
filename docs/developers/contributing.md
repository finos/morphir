---
id: contribution-and-governance-policies
---

# Governance Policies

This document describes the contribution process and governance policies of the FINOS Morphir project. The project is also governed by the Linux Foundation Antitrust Policy, and the FINOS IP Policy, Code of Conduct, Collaborative Principles, and Meeting Procedures.

When contributing to this repository, please first discuss the change you wish
to make via issue, email, or any other method with the owners of this repository
before making a change.

Please note we have a code of conduct, please follow it in all your interactions
with the project.

## Contribution Process

Before making a contribution, please take the following steps:
1. Check whether there's already an open issue related to your proposed contribution. If there is, join the discussion and propose your contribution there.
2. If there isn't already a relevant issue, create one, describing your contribution and the problem you're trying to solve.
3. Respond to any questions or suggestions raised in the issue by other developers.
4. Fork the project repository and prepare your proposed contribution.
5. Submit a pull request.

NOTE: All contributors must have a contributor license agreement (CLA) on file with FINOS before their pull requests will be merged. Please review the FINOS [contribution requirements](https://finosfoundation.atlassian.net/wiki/spaces/FINOS/pages/75530375/Contribution+Compliance+Requirements) and submit (or have your employer submit) the required CLA before submitting a pull request.

## Contributing Issues

### Prerequisites

* [ ] Have you [searched for duplicates](https://github.com/finos/morphir/issues?utf8=%E2%9C%93&q=)?  A simple search for exception error messages or a summary of the unexpected behaviour should suffice.
* [ ] Are you running the latest version?
* [ ] Are you sure this is a bug or missing capability?

### Raising an Issue
* Create your issue [here](https://github.com/finos/morphir/issues/new).
* New issues contain two templates in the description: bug report and enhancement request. Please pick the most appropriate for your issue, **then delete the other**.
  * Please also tag the new issue with either "Bug" or "Enhancement".
* Please use [Markdown formatting](https://help.github.com/categories/writing-on-github/)
liberally to assist in readability.
  * [Code fences](https://help.github.com/articles/creating-and-highlighting-code-blocks/) for exception stack traces and log entries, for example, massively improve readability.

## Contributing Pull Requests (Code & Docs)
To make review of PRs easier, please:

 * Please make sure your PRs will merge cleanly - PRs that don't are unlikely to be accepted.
 * For code contributions, follow the existing code layout.
 * For documentation contributions, follow the general structure, language, and tone of the [existing docs](https://github.com/finos/morphir/wiki).
 * Keep commits small and cohesive - if you have multiple contributions, please submit them as independent commits (and ideally as independent PRs too).
 * Reference issue #s if your PR has anything to do with an issue (even if it doesn't address it).
 * Minimise non-functional changes (e.g. whitespace).
 * Ensure all new files include a header comment block containing the [Apache License v2.0 and your copyright information](http://www.apache.org/licenses/LICENSE-2.0#apply).
 * If necessary (e.g. due to 3rd party dependency licensing requirements), update the [NOTICE file](https://github.com/finos/morphir/blob/master/NOTICE) with any new attribution or other notices

### Before your first pull request

If you have not previously contributed to the project, 
you must first create a *Developer Certificate of Origin* (“DCO”) and include a 
reference to this DCO in each of your commits.  In addition, if you subsequently 
wish to contribute code having a different copyright ownership, then you must create 
a new DCO for such contribution.

To create a DCO please follow these steps:

1. For code you are contributing, determine who is/are the copyright owner(s). 
Please note that your employer may own the copyright in code you have written even 
where the code was not created during regular working hours.  Copyright law is
variable from jurisdiction to jurisdiction. Accordingly, consult your employer
or a lawyer if you are not sure.
2. Fill out the [DCO] replacing all `<>` terms as appropriate, and place the 
completed DCO in a file under `dco/<your name>` or if you are not the copyright 
holder then in a file under `dco/<your name>-<copyright holder name(s)>`.
    1. Please note that the name you provide (`<your name>`) must be your real 
       (legal) name; we will not accept aliases, pseudonyms or anonymous 
       contributions.
    1. If you’ve determined that the copyright holder of the code that you’ve 
       written is an entity other than yourself (e.g., your employer), then 
       include the legal name of the copyright holder(s) (`<name of copyright holder(s)>`).
       You must ensure that you are authorized by the copyright holder(s) to be able 
       to grant the licenses under the DCO for the purpose of contributing to the 
       project. Negotiating such authorization and administering the terms is 
       entirely between you and the copyright holder(s).
3. Issue a pull request with the DCO.

### Pull request process 

When you create a pull request, follow these steps:

1. Your commit message for the code you are submitting must include a
`“Covered by <dco>“` line which indicates your acceptance of the DCO terms and conditions. 
`<dco>` here is the file name of the DCO.
2. Your commit must include a change to the `NOTICE.txt` file that contains complete
details of any applicable copyright notice for your submission and including any
applicable third party license(s) or other restrictions associated with any part
of your contribution, and of all matters required to be disclosed under such third
party license(s) (such as any applicable copyright, patent, trademark, and attribution
notices, and any notices relating to modifications made to open source software).
Note your contribution must retain all applicable copyright, patent, trademark and
attribution notices.

### Pull request guidelines

* Update the `README.md` docs with details of changes to API, behaviour, features, or usage.
Include useful file locations and relevant documentation.
* Update an existing or add a new testcase for your change. 
* Ensure any install or build artefacts are removed from the pull request.
* We generally prefer squashed commits, unless multi-commits add clarity or are 
required for mixed copyright commits.
* You may merge the Pull Request in once the build has passed and you have the sign-off 
of one other developer, or if you do not have permission to do that, you may request the 
reviewer to merge it for you. 

### Commit and PR Messages

* **Reference issues, wiki pages, and pull requests liberally!**
* Use the present tense ("Add feature" not "Added feature")
* Use the imperative mood ("Move button left..." not "Moves button left...")
* Limit the first line to 72 characters or less
   
## Code of Conduct

### Our Pledge

In the interest of fostering an open and welcoming environment, we as
contributors and maintainers pledge to making participation in our project and
our community a harassment-free experience for everyone, regardless of age, body
size, disability, ethnicity, gender identity and expression, level of experience,
nationality, personal appearance, race, religion, or sexual identity and
orientation.

### Our Standards

Examples of behavior that contributes to creating a positive environment
include:

* Using welcoming and inclusive language
* Being respectful of differing viewpoints and experiences
* Gracefully accepting constructive criticism
* Focusing on what is best for the community
* Showing empathy towards other community members

Examples of unacceptable behavior by participants include:

* The use of sexualized language or imagery and unwelcome sexual attention or
advances
* Trolling, insulting/derogatory comments, and personal or political attacks
* Public or private harassment
* Publishing others' private information, such as a physical or electronic
  address, without explicit permission
* Other conduct which could reasonably be considered inappropriate in a
  professional setting

### Our Responsibilities

Project maintainers are responsible for clarifying the standards of acceptable
behavior and are expected to take appropriate and fair corrective action in
response to any instances of unacceptable behavior.

Project maintainers have the right and responsibility to remove, edit, or
reject comments, commits, code, wiki edits, issues, and other contributions
that are not aligned to this Code of Conduct, or to ban temporarily or
permanently any contributor for other behaviors that they deem inappropriate,
threatening, offensive, or harmful.

### Scope

This Code of Conduct applies both within project spaces and in public spaces
when an individual is representing the project or its community. Examples of
representing a project or community include using an official project e-mail
address, posting via an official social media account, or acting as an appointed
representative at an online or offline event. Representation of a project may be
further defined and clarified by project maintainers.

### Enforcement

Instances of abusive, harassing, or otherwise unacceptable behavior may be
reported by contacting the project team at morphir-dev [at] morganstanley.com. All
complaints will be reviewed and investigated and will result in a response that
is deemed necessary and appropriate to the circumstances. The project team is
obligated to maintain confidentiality with regard to the reporter of an incident.
Further details of specific enforcement policies may be posted separately.

Project maintainers who do not follow or enforce the Code of Conduct in good
faith may face temporary or permanent repercussions as determined by other
members of the project's leadership.

### Attribution

This Code of Conduct is adapted from the [Contributor Covenant][homepage],
version 1.4, available at [http://contributor-covenant.org/version/1/4][version]

[homepage]: http://contributor-covenant.org
[version]: http://contributor-covenant.org/version/1/4/
[DCO]: dco/dco_template.md

## Governance

### Roles

The project community consists of Contributors and Maintainers:
* A **Contributor** is anyone who submits a contribution to the project. (Contributions may include code, issues, comments, documentation, media, or any combination of the above.)
* A **Maintainer** is a Contributor who, by virtue of their contribution history, has been given write access to project repositories and may merge approved contributions.
* The **Lead Maintainer** is the project's interface with the FINOS team and Board. They are responsible for approving [quarterly project reports](https://finosfoundation.atlassian.net/wiki/spaces/FINOS/pages/93225748/Board+Reporting+and+Program+Health+Checks) and communicating on behalf of the project. The Lead Maintainer is elected by a vote of the Maintainers. 

### Contribution Rules

Anyone is welcome to submit a contribution to the project. The rules below apply to all contributions. (The key words "MUST", "SHALL", "SHOULD", "MAY", etc. in this document are to be interpreted as described in [IETF RFC 2119](https://www.ietf.org/rfc/rfc2119.txt).)

* All contributions MUST be submitted as pull requests, including contributions by Maintainers.
* All pull requests SHOULD be reviewed by a Maintainer (other than the Contributor) before being merged.
* Pull requests for non-trivial contributions SHOULD remain open for a review period sufficient to give all Maintainers a sufficient opportunity to review and comment on them.
* After the review period, if no Maintainer has an objection to the pull request, any Maintainer MAY merge it.
* If any Maintainer objects to a pull request, the Maintainers SHOULD try to come to consensus through discussion. If not consensus can be reached, any Maintainer MAY call for a vote on the contribution.

### Maintainer Voting

The Maintainers MAY hold votes only when they are unable to reach consensus on an issue. Any Maintainer MAY call a vote on a contested issue, after which Maintainers SHALL have 36 hours to register their votes. Votes SHALL take the form of "+1" (agree), "-1" (disagree), "+0" (abstain). Issues SHALL be decided by the majority of votes cast. If there is only one Maintainer, they SHALL decide any issue otherwise requiring a Maintainer vote. If a vote is tied, the Lead Maintainer MAY cast an additional tie-breaker vote.

The Maintainers SHALL decide the following matters by consensus or, if necessary, a vote:
* Contested pull requests
* Election and removal of the Lead Maintainer
* Election and removal of Maintainers

All Maintainer votes MUST be carried out transparently, with all discussion and voting occurring in public, either:
* in comments associated with the relevant issue or pull request, if applicable;
* on the project mailing list or other official public communication channel; or
* during a regular, minuted project meeting.

### Maintainer Qualifications

Any Contributor who has made a substantial contribution to the project MAY apply (or be nominated) to become a Maintainer. The existing Maintainers SHALL decide whether to approve the nomination according to the Maintainer Voting process above.

### Changes to this Document

This document MAY be amended by a vote of the Maintainers according to the Maintainer Voting process above.