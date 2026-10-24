# Roc nightly updates

This repository checks once daily at 13:19 UTC, about four hours
after the upstream 09:00 UTC build. Late publication can wait until the next day.

`.roc-version` is the compiler pin. `.github/roc-nightly.json` selects this
repository's validation workflows, including their validation-only release paths.
The controller, its tests, and job permissions are maintained in
[roc-automation](https://github.com/lukewilliamboswell/roc-automation).
The caller workflows pin shared code to `7aff4132691ad4fc348abe9df146a57512b49bd6`
(roc-automation `tools-0.4.0`). Dependabot proposes reviewed updates to
Actions/workflow references.

Follow the shared [repository settings](https://github.com/lukewilliamboswell/roc-automation/blob/7aff4132691ad4fc348abe9df146a57512b49bd6/docs/settings.adoc)
for action allowlists at full SHAs, required checks and signed commits. Keep
default token permissions read-only. Unlike the shared model, which floats the
package compiler and opens no pull requests, this repository pins the compiler
because its allocation baselines are exact for one build. The updater therefore
needs "Allow GitHub Actions to create and approve pull requests" for its
pin-only PR, and its first live GITHUB_TOKEN run must be verified after merge. The updater merges
only its signed, pin-only PR after the configured validation workflows succeed
and the live strict ruleset accepts the exact candidate. It receives no
protection bypass.

`automation/roc-nightly` is reserved for the bot's pin-only commits. Put manual
compatibility changes on a separate branch. Candidate failures require diagnosis;
do not weaken tests or mechanically replace baselines to accept a compiler.

The PR configuration check validates the local pin and selected workflow files.
The shared repository owns the controller regression suite. Project tests remain
in this repository and run on the exact candidate commit. Scheduled bot-token
acceptance must be verified after merge; file changes alone cannot prove it.

Use the shared [project-practice evidence](https://github.com/lukewilliamboswell/roc-automation/blob/7aff4132691ad4fc348abe9df146a57512b49bd6/docs/project-practices.adoc)
to record project-specific evidence. This integration does not establish badge
compliance or change repository settings.
