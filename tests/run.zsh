#!/usr/bin/env zsh

emulate -L zsh
setopt ERR_EXIT NO_UNSET PIPE_FAIL

ROOT="${0:A:h:h}"
RECONCILE="$ROOT/bin/my-repo-skills-reconcile"
SANDBOX="$(mktemp -d)"
SANDBOX="${SANDBOX:A}"
trap 'rm -rf "$SANDBOX"' EXIT

passed=0
pass() {
  (( passed += 1 ))
  print "ok $passed - $1"
}

assert() {
  "$@" || {
    print -u2 -- "not ok - $*"
    exit 1
  }
}

new_repo() {
  local repo_path="$1" remote="$2"
  mkdir -p "$repo_path"
  git -C "$repo_path" init -q
  git -C "$repo_path" config user.name Test
  git -C "$repo_path" config user.email test@example.com
  git -C "$repo_path" remote add origin "$remote"
}

registry="$SANDBOX/registry"
repo="$SANDBOX/work repo"
target="$registry/github.com/acme/widget"
mkdir -p "$target/example-skill"
print -- $'---\nname: example-skill\ndescription: Test fixture.\n---' > "$target/example-skill/SKILL.md"
new_repo "$repo" "https://github.com/acme/widget.git"

MY_REPO_SKILLS_DIR="$registry" "$RECONCILE" --quiet --cwd "$repo"
assert test "$(readlink "$repo/.agents/skills/_my-repo-skills")" = "$target"
assert test "$(readlink "$repo/.claude/skills/_my-repo-skills")" = "$target"
assert test -f "$repo/.agents/skills/_my-repo-skills/example-skill/SKILL.md"
assert test -z "$(git -C "$repo" status --porcelain)"
pass "HTTPS remote creates ignored adapters in a path with spaces"

before="$(readlink "$repo/.agents/skills/_my-repo-skills")"
MY_REPO_SKILLS_DIR="$registry" "$RECONCILE" --quiet --cwd "$repo"
assert test "$(readlink "$repo/.agents/skills/_my-repo-skills")" = "$before"
pass "reconciliation is idempotent"

ssh_repo="$SANDBOX/ssh-repo"
new_repo "$ssh_repo" "git@github.com:acme/widget.git"
MY_REPO_SKILLS_DIR="$registry" "$RECONCILE" --quiet --cwd "$ssh_repo"
assert test -L "$ssh_repo/.agents/skills/_my-repo-skills"
pass "SSH and HTTPS remotes normalize to the same identity"

unmatched="$SANDBOX/unmatched"
new_repo "$unmatched" "https://github.com/acme/other.git"
MY_REPO_SKILLS_DIR="$registry" "$RECONCILE" --quiet --cwd "$unmatched"
assert test ! -e "$unmatched/.agents/skills/_my-repo-skills"
pass "an unmatched repository is untouched"

collision="$SANDBOX/collision"
new_repo "$collision" "https://github.com/acme/widget.git"
mkdir -p "$collision/.agents/skills/_my-repo-skills"
if MY_REPO_SKILLS_DIR="$registry" "$RECONCILE" --quiet --cwd "$collision" 2>/dev/null; then
  print -u2 "not ok - unmanaged collision should fail"
  exit 1
fi
pass "an unmanaged adapter is never overwritten"

ambiguous="$SANDBOX/ambiguous"
new_repo "$ambiguous" "https://github.com/acme/widget.git"
git -C "$ambiguous" remote add upstream "https://gitlab.com/acme/widget.git"
mkdir -p "$registry/gitlab.com/acme/widget/another-skill"
print -- $'---\nname: another-skill\ndescription: Test fixture.\n---' > "$registry/gitlab.com/acme/widget/another-skill/SKILL.md"
if MY_REPO_SKILLS_DIR="$registry" "$RECONCILE" --quiet --cwd "$ambiguous" 2>/dev/null; then
  print -u2 "not ok - ambiguous mappings should fail"
  exit 1
fi
pass "multiple matching remotes fail loudly"

git -C "$repo" commit --allow-empty -qm init
worktree="$SANDBOX/widget-worktree"
git -C "$repo" worktree add -q -b test-worktree "$worktree"
MY_REPO_SKILLS_DIR="$registry" "$RECONCILE" --quiet --cwd "$worktree"
assert test -L "$worktree/.agents/skills/_my-repo-skills"
assert test -z "$(git -C "$worktree" status --porcelain)"
pass "linked Git worktrees receive clean adapters"

rm -rf "$target"
MY_REPO_SKILLS_DIR="$registry" "$RECONCILE" --quiet --cwd "$repo"
assert test ! -L "$repo/.agents/skills/_my-repo-skills"
assert test ! -L "$repo/.claude/skills/_my-repo-skills"
pass "stale managed adapters are removed"

print "1..$passed"
