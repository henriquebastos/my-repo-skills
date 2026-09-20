# Customizing and extending

This guide is for people adapting My Repo Skills to another shell, agent tool,
forge, or workstation layout. Read the [technical overview](technical-overview.md)
first.

## Preserve the core contract

The implementation is small, but several behaviors are deliberate invariants:

- The implementation and private skill registry are separate.
- Repository identity comes from Git remotes, not checkout directory names.
- Identity includes the hostname.
- No tracked project file is required. Keep the reserved adapter paths untracked.
- Reconciliation is idempotent.
- Wrong links, files, and directories at reserved adapter paths are replaced when one current mapping matches.
- Multiple different matches fail rather than relying on remote ordering.
- The public implementation repository contains no skills or mappings.

Extensions should preserve these properties unless they clearly document a
changed trust or ownership model.

## Supported customization points

### Move the private registry

Set `MY_REPO_SKILLS_DIR` before sourcing the Zsh initializer:

```zsh
export MY_REPO_SKILLS_DIR="$HOME/private/agent-skills-by-repository"
source ~/.local/share/my-repo-skills/zsh/my-repo-skills-reconcile.zsh
```

The variable points directly to the directory containing host directories. The
reconciler does not append another `skills/` component.

Adapters use absolute symlink targets. After a registry move, reconcile each
checkout with the new `MY_REPO_SKILLS_DIR`. If one current mapping matches,
the reconciler replaces any wrong link, file, or directory at its reserved
adapter paths. No previous registry setting or manual cleanup is needed.

### Use a different implementation checkout

The sourced initializer locates `bin/` relative to itself, so the implementation
can be cloned anywhere. Update the source line if the checkout moves. The
private registry does not move with it and is unaffected by implementation
updates.

### Trigger reconciliation another way

The executable is independent of the supplied `chpwd` hook:

```text
my-repo-skills-reconcile [--quiet] [--cwd <directory>]
```

A Bash, Fish, editor, terminal, or directory-environment integration can invoke
that command from its own directory-change event. Zsh must still be installed
because the executable itself is Zsh.

Custom triggers should pass the checkout being entered, avoid running
concurrently when possible, and surface nonzero exits. Do not discard filesystem
or ambiguity failures merely because the default hook normally uses `--quiet`;
`--quiet` suppresses successful status messages, not errors.

### Support another agent tool

Adapter paths are declared in the `ADAPTERS` array near the top of
`bin/my-repo-skills-reconcile`. To add a tool:

1. Confirm the tool supports project-local discovery through a directory.
2. Add one stable adapter path to `ADAPTERS`.
3. Ensure its parent directories may be created safely.
4. Verify the adapter is added to Git's local exclude file.
5. Add tests for creation, idempotence, adapter replacement, stale cleanup, and clean
   `git status`.
6. Document which versions of the tool support that discovery path.

All adapters currently point to the same repository mapping. If a tool requires
a different skill format rather than a different discovery path, a symlink-only
adapter may not be sufficient; format conversion is outside the current model.

### Support another remote form or forge

The current normalizer accepts:

- URLs containing a scheme, such as HTTPS and `ssh://`;
- SCP-like SSH remotes, such as `git@host:owner/repository.git`.

Plain local filesystem paths and hostless `file://` URLs do not produce
repository identities. The normalizer does not restrict URL schemes, so
`file://localhost/srv/acme/api.git` normalizes to `localhost/srv/acme/api`.
Scheme URL ports are discarded, IPv6 authorities are not specially parsed, and
query strings or fragments are not normalized. The host is lowercased while the
repository path preserves case.

Nested forge groups work naturally because everything after the host is kept as
the repository path. For example, a GitLab remote may map to:

```text
gitlab.example.com/group/subgroup/repository
```

When expanding normalization, add fixtures for every accepted form and for
nearby malformed inputs. Avoid heuristics based on remote names such as
`origin`; forks and migrations commonly use `upstream` or custom names.

### Change matching policy

The default policy considers every remote and deduplicates remotes that resolve
to the same registry directory. Different matching directories are an error.

Possible alternatives—preferred remote names, explicit precedence, profiles,
or per-clone configuration—change the predictability and portability of the
system. They are intentionally absent from version 1. If added, make precedence
observable and preserve a fail-loud mode.

## What the reconciler does not validate

My Repo Skills matches repository directories and creates adapters. It does not
parse `SKILL.md`, validate frontmatter, determine whether a tool accepts a
skill, or inspect the safety of skill instructions. Those concerns belong to
the consuming agent tool and the user maintaining the private registry.

A matching repository directory can therefore be empty. Reconciliation will
still create adapters, but agent tools will discover no usable skills until the
registry contains valid skill directories.

## Cleanup behavior

There is no global index of checkouts that received adapters. Reconciliation can
clean only the checkout passed to it.

When a mapping is removed within the same registry root, the next reconciliation
of that checkout removes adapters whose targets remain recognizably inside that
registry. After a registry move, a matching current directory replaces the old
adapters. Without a current match, links outside the current registry remain
unchanged. Uninstalling or never revisiting a worktree requires manual cleanup. Git exclude
entries are intentionally left behind because they are harmless and may be
shared by linked worktrees.

## Zsh implementation notes

Several Zsh details are easy to miss when modifying the scripts:

- `path` is a special array tied to `PATH`. Do not reuse `path` as an ordinary
  local variable; doing so can make external commands disappear inside a
  function.
- Associative-array keys containing filesystem paths require careful expansion.
  Convert key sets to a real array before indexing; indexing a scalar expansion
  can return a character instead of a key.
- `${value:A}` canonicalizes paths. On macOS this also resolves aliases such as
  `/var` to `/private/var`, so tests should compare canonical paths.
- The initializer is sourced rather than executed. Keep its global state names
  specific to My Repo Skills and make repeated sourcing safe.
- `.git` is a directory in a normal checkout and a file in a linked worktree.
  Trigger logic must accept both.

These are implementation constraints, not merely style preferences; regressions
in them can silently disable command lookup or produce incorrect symlinks.

## Test expectations

Run the complete test suite after behavior changes:

```bash
tests/run.zsh
```

The suite creates disposable Git repositories and currently protects:

- HTTPS and SCP-like SSH normalization;
- paths containing spaces;
- idempotent reconciliation;
- unmatched-repository behavior;
- replacement of wrong symlinks, files, and directories at reserved adapter paths;
- ambiguous remote failure;
- linked worktree behavior;
- stale managed-adapter removal;
- clean Git status.

New customization points should add an integration-level fixture. Tests should
assert both the intended filesystem result and the absence of project Git
changes. Syntax checks alone do not exercise Zsh expansion and path semantics.

## Troubleshooting

### The command is not found

Start a new Zsh or source the initializer again. Then inspect:

```zsh
print -r -- $commands[my-repo-skills-reconcile]
print -r -- $MY_REPO_SKILLS_DIR
```

The command should resolve inside the implementation checkout's `bin/`
directory.

### No adapter appears

Check the inputs in order:

```bash
git rev-parse --show-toplevel
git config --get-regexp '^remote\..*\.url$'
my-repo-skills-reconcile --cwd "$PWD"
```

Then compare the normalized remote identity with the directory hierarchy under
`MY_REPO_SKILLS_DIR`. Run without `--quiet` when diagnosing manually.

### Reconciliation reports multiple matches

Two or more remotes correspond to different mapping directories. Remove the
unintended mapping or remote. The reconciler will not guess which repository
identity should win.

### An existing adapter points elsewhere

Run reconciliation with the current `MY_REPO_SKILLS_DIR`. If one mapping matches,
the reserved adapter path is replaced automatically. A file or directory at that
path is also replaced. Keep other content outside these reserved paths.

### The adapter exists but the agent sees no skills

Confirm that:

1. the symlink resolves to the intended mapping;
2. valid skill directories exist directly below that mapping;
3. the agent version supports the relevant discovery path;
4. the agent was started in the intended checkout or worktree;
5. the agent has been restarted if it caches discovery at startup.

### A remote or mapping changed but nothing happened

The Zsh hook caches the current worktree. Run the reconciler manually, or leave
and re-enter the worktree, to force another match.

## Non-goals for version 1

My Repo Skills is not currently:

- a skill package manager;
- a registry synchronization service;
- a secret manager;
- a cross-shell installer;
- a repository-profile or precedence system;
- a daemon that watches remotes and files;
- a compatibility layer between different skill formats.

Keeping these non-goals explicit helps extensions solve observed problems
without turning the reference implementation into an implicit platform.
