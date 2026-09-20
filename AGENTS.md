# Agent instructions

My Repo Skills is a small Zsh reference implementation, not a package manager.

- Keep version 1 compatible with Zsh 5.8+ and Git 2.31+.
- Do not add Python, Node, package-manager, or framework dependencies.
- Keep the public repository free of skills, repository mappings, and credentials.
- Treat both `_my-repo-skills` adapter paths as reserved. Replace wrong links, files, and directories when one current mapping matches.
- Preserve fail-loud ambiguity handling and clean `git status` behavior.
- Run `tests/run.zsh` after behavior changes.
- Update `README.md` and `INSTALL.md` when installation or layout changes.
