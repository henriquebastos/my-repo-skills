# My Repo Skills

Personal agent skills scoped to Git repositories without putting them in the
project.

Project skills belong to a repository and are shared with its contributors.
**My repo skills** belong to you: they live outside the project, but become
available automatically whenever you enter a matching checkout or worktree.

## How it works

A Git remote is normalized into a directory identity:

```text
git@github.com:acme/api.git
https://github.com/acme/api.git
                           → github.com/acme/api
```

If that identity exists under your private skill registry, the reconciler adds
ignored adapters to the checkout:

```text
.agents/skills/_my-repo-skills   → your matching skill directory
.claude/skills/_my-repo-skills   → your matching skill directory
```

Pi, Codex, Amp, and tools that discover `.agents/skills` use the first adapter.
Claude Code uses the second. Exact adapter paths are added to the repository's
shared `.git/info/exclude`, so they stay out of `git status` across worktrees.

See [Technical overview](docs/technical-overview.md) for the problem this solves,
the trigger lifecycle, reconciliation algorithm, safety model, and complete user
workflow. See [Customizing and extending](docs/customizing-and-extending.md) for
supported extension points, invariants, troubleshooting, and developer notes.

## Requirements

Version 1 intentionally targets a small environment:

- Zsh 5.8 or newer
- Git 2.31 or newer
- macOS or another Unix-like system with symlink support

## Install

Clone this repository wherever you keep tools:

```bash
git clone https://github.com/henriquebastos/my-repo-skills.git \
  ~/.local/share/my-repo-skills
```

Source one file from `.zshrc`:

```zsh
source ~/.local/share/my-repo-skills/zsh/my-repo-skills-reconcile.zsh
```

The sourced file adds this repository's `bin/` directory to `PATH`, configures
the default registry, installs a `chpwd` hook, and reconciles the current
working directory.

The default registry is:

```text
~/.agents/my-repo-skills/skills
```

`XDG_CONFIG_HOME` does not affect this default. Existing registries are not moved
automatically. To keep an existing registry, set `MY_REPO_SKILLS_DIR` to its path.

Override it before sourcing when desired:

```zsh
export MY_REPO_SKILLS_DIR="$HOME/somewhere/private/my-repo-skills"
source ~/.local/share/my-repo-skills/zsh/my-repo-skills-reconcile.zsh
```

## Add a repository skill

Given a repository with this remote:

```text
https://github.com/acme/api.git
```

create:

```text
~/.agents/my-repo-skills/skills/
└── github.com/
    └── acme/
        └── api/
            └── deploy-preview/
                └── SKILL.md
```

The repository directory contains skill directories directly. The hostname is
kept to avoid collisions between GitHub, GitLab, self-hosted forges, and future
repository migrations.

Enter the repository or run reconciliation manually:

```bash
my-repo-skills-reconcile --cwd /path/to/api
```

## Safety properties

The reconciler:

- creates no adapters when no registry directory matches;
- considers every configured remote, including `upstream`;
- is idempotent;
- replaces wrong symlinks, files, and directories at its reserved adapter paths;
- fails when different remotes match multiple registry directories;
- removes stale adapters that it owns;
- leaves project files outside its reserved adapter paths unchanged.

Skills are executable instructions. A repository controls its own remote
configuration, so only use mappings with repositories you trust.

## Test

```bash
tests/run.zsh
```

The tests use temporary repositories and cover HTTPS and SSH remotes, paths with
spaces, idempotence, adapter replacement, ambiguous remotes, linked worktrees, stale
cleanup, and clean Git status.

## Uninstall

Remove the source line from `.zshrc`, then remove the two `_my-repo-skills`
symlinks from any currently linked checkout. The local exclude entries are
harmless if left in place.

## Scope

This is a reference implementation and a set of inspectable snippets, not a
package manager or hosted product.
