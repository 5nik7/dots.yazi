# Contributing

Start with [AGENTS.md](AGENTS.md), [architecture](docs/architecture.md) and
[testing](docs/testing.md). Keep changes focused and preserve compatibility with
existing setup tables. Explain the observable behavior and how it was verified.

Keep UI rendering free of subprocesses and file reads. New settings belong in
README examples and the appropriate component; shared theme data belongs to the
Dots publisher, not a second palette parser embedded in individual components.

If a change also updates the main Dots checkout, inspect both Git states first.
Copy only reviewed shared runtime files, preserving the bundled copy's read-only
permissions. Run the consistency checker in Dots and validate its real source
config through the isolated native runner. Commit histories remain independent.
