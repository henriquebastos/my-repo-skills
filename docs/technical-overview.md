# Technical overview

For supported customization points, implementation invariants, troubleshooting,
and developer notes, see [Customizing and extending](customizing-and-extending.md).

## The problem

Agent skills usually have two natural homes:

1. **Global skills** are available in every repository.
2. **Project skills** are committed with a repository and shared with everyone
   who checks it out.

A third category does not fit either model: a skill that is personal, but only
useful in one repository. Examples include an individual's deployment routine,
private issue-tracker context, or a workflow that depends on local tooling.
Making such a skill global exposes irrelevant instructions in every project.
Committing it to the project mixes personal context into shared source control.
Copying it into every checkout and worktree creates drift.

My Repo Skills provides this missing scope. Personal skills stay in a private
registry outside the project, while small local adapters make the matching set
visible through agent tools' normal project-level discovery paths.

## Design in one sentence

A Git remote identifies the repository; a matching directory in the user's
private registry becomes the target of ignored symlinks inside each checkout or
worktree.

The implementation is intentionally filesystem-based. It does not patch agent
tools, run a daemon, maintain a database, or introduce a new skill format.

## Components

My Repo Skills has three parts:

### 1. The implementation checkout

This public repository contains the generic Zsh implementation:

```text
bin/my-repo-skills-reconcile
zsh/my-repo-skills-reconcile.zsh
```

It contains no user skills or repository mappings.

### 2. The private registry

By default, personal mappings live at:

```text
~/.agents/my-repo-skills/skills/
└── <host>/
    └── <owner>/
        └── <repository>/
            ├── <skill-one>/
            └── <skill-two>/
```

`MY_REPO_SKILLS_DIR` can point somewhere else. The directory named by that
variable is the mapping root itself: it directly contains host directories.
`XDG_CONFIG_HOME` does not affect the default.

The hostname is part of the identity. This prevents `acme/api` on GitHub from
colliding with `acme/api` on GitLab or an internal forge.

### 3. Checkout adapters

For a matching repository, the reconciler creates:

```text
.agents/skills/_my-repo-skills
.claude/skills/_my-repo-skills
```

Both are symlinks to the matching registry directory. Tools that discover
`.agents/skills` use the first adapter; Claude Code uses the second. The tools
continue reading ordinary skill directories and files—the adapter only exposes
them at the location each tool already understands.

## What triggers reconciliation

Sourcing `zsh/my-repo-skills-reconcile.zsh` from `.zshrc` performs four setup
steps:

1. Resolve the implementation checkout from the sourced file's own location.
2. Add its `bin/` directory to `PATH`.
3. Set the default registry unless `MY_REPO_SKILLS_DIR` is already configured.
4. register a Zsh `chpwd` hook and reconcile the current directory immediately.

After shell startup, reconciliation runs when Zsh changes directory into a
different Git checkout or worktree. The hook walks upward from `$PWD` until it
finds a `.git` file or directory, then invokes:

```text
my-repo-skills-reconcile --quiet --cwd <worktree-root>
```

The hook caches the last worktree root, so moving among subdirectories of the
same worktree does not repeatedly run Git or touch the filesystem. Leaving Git
worktrees resets that cache.

There is no filesystem watcher or background process. If remotes or registry
mappings change while the shell remains inside the same worktree, run the
command manually or leave and re-enter the worktree.

The adapters persist after creation. This is deliberate: agent processes can
discover the skills later without depending on the shell hook still running.

## Reconciliation algorithm

The executable follows this sequence:

1. Ask Git for the checkout or worktree root. Outside Git, exit successfully.
2. Resolve the private registry to an absolute path.
3. Read every `remote.*.url`, not only `origin`.
4. Normalize each supported remote URL into `<host>/<owner>/<repository>`.
5. Check whether each normalized identity exists below the registry.
6. Fail if different remotes match more than one registry directory.
7. If exactly one directory matches, safely create or update both adapters.
8. Add the exact adapter paths to Git's local `info/exclude` file.

If nothing matches, the reconciler removes only stale adapters that point into
the configured registry. Unrelated files and symlinks are left untouched.

### Remote normalization

These common remote forms resolve to the same identity:

```text
https://github.com/acme/api.git
ssh://git@github.com/acme/api.git
git@github.com:acme/api.git

→ github.com/acme/api
```

The hostname is lowercased, a leading path slash and trailing slash are removed,
and a trailing `.git` suffix is stripped. The remaining owner and repository
path keeps its original case.

All configured remotes participate. This allows a personal mapping to match a
fork's `upstream` remote, but it also means two independently mapped remotes are
ambiguous. Ambiguity fails loudly rather than selecting one by remote name or
ordering.

## Why Git stays clean

The adapters live inside the checkout so project-scoped discovery works, but
they must never appear as project changes. The reconciler adds these exact
patterns to the repository's Git-local exclude file:

```text
/.agents/skills/_my-repo-skills
/.claude/skills/_my-repo-skills
```

`info/exclude` is local Git metadata rather than a tracked `.gitignore`, so the
project repository is not modified. Linked worktrees use Git's resolved
`--git-path info/exclude` location, allowing the exclusion to apply without
committing anything to the project.

## Safety and ownership rules

The two `_my-repo-skills` adapter paths belong to the reconciler. When exactly
one current mapping matches, it:

- reuses an adapter that already points to that mapping;
- replaces any other symlink without changing its former target;
- removes a file or directory at the reserved path and creates the adapter;
- leaves other project paths unchanged.

Multiple matching directories cause an error before any adapter changes.
Without a match, cleanup removes only symlinks whose targets resolve inside
the current registry. Keep the reserved adapter paths untracked and free of
other content.

The registry is still executable agent context. A repository controls its Git
remote configuration, so only map repositories you trust. Keep credentials out
of skill files unless the chosen skill system explicitly provides a secure
secret mechanism.

## User workflow

### Install once

Clone the implementation and source its Zsh initializer:

```zsh
source ~/.local/share/my-repo-skills/zsh/my-repo-skills-reconcile.zsh
```

Restart Zsh or source the updated shell configuration.

### Add a mapping

1. Inspect the target repository's remotes with `git remote -v`.
2. Choose the intended remote identity.
3. Create `<host>/<owner>/<repository>` under the private registry.
4. Put the personal skill directories directly inside that repository
   directory.
5. Enter the checkout, or run the reconciler manually.
6. Confirm the adapters resolve to the intended registry directory.
7. Confirm `git status` remains unchanged.

### Use the skills

Start the agent tool normally from the repository or worktree. No My Repo
Skills-specific command is required after reconciliation: the agent sees the
skills through its existing project discovery mechanism.

### Change or remove a mapping

Changes inside the registry are immediately visible through existing symlinks.
After moving or deleting a mapping within the same registry root, manually
reconcile affected checkouts or leave and re-enter them. The reconciler removes
stale adapters it owns when the repository no longer matches.

After changing the registry root, reconcile with the new `MY_REPO_SKILLS_DIR`.
A matching current directory replaces the old adapter automatically.

## Scope and tradeoffs

Version 1 favors an inspectable mechanism over broad portability:

- Zsh 5.8+ performs installation and triggering.
- Git 2.31+ provides repository identity and local exclude paths.
- Unix symlinks provide adapters.
- Remote URL identity is automatic but depends on configured remotes.
- Reconciliation is event-driven by shell directory changes, not real-time.
- Supported agent tools must discover `.agents/skills` or `.claude/skills`.

These constraints keep the complete mechanism small enough to read, audit, and
adapt without a package manager or resident service.
