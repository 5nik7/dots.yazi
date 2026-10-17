# Contributing

Start with [AGENTS.md](AGENTS.md), [architecture](docs/architecture.md) and
[testing](docs/testing.md). Keep changes focused and preserve compatibility with
existing setup tables. Explain the observable behavior and how it was verified.

Keep UI rendering free of subprocesses and file reads. New settings belong in
README examples and the appropriate component; shared theme data belongs to the
Dots publisher, not a second palette parser embedded in individual components.

If a change also updates the main Dots checkout, inspect both Git states first.
Validate its candidate configuration through the isolated native runner. For
remote-installed packages, publish the standalone source and use `ya pkg upgrade
5nik7/dots`; never patch installed files, discard local changes or rewrite hashes.
Run Dots' consistency checker after the update. Commit histories remain independent.
