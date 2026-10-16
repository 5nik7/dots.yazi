# Repository-local Codex workflows

Skills live here and are discoverable through regular directories under
.agents/skills, with relative file symlinks for SKILL.md and agents/openai.yaml.
Yazi packages accept file symlinks but reject directory symlinks; keep discovery
directories real so `ya pkg add 5nik7/dots` can materialize the package.
AGENTS.md remains the operating contract; skills point to maintained project docs.
This directory is not a replacement CODEX_HOME and contains no credentials, model
selection, permission overrides, sessions or machine-local state.

- [dots-yazi-ui](skills/dots-yazi-ui/SKILL.md)
- [dots-yazi-validation](skills/dots-yazi-validation/SKILL.md)
