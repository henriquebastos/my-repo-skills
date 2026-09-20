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

test_home="$SANDBOX/home with spaces"
default_registry="$test_home/.agents/my-repo-skills/skills"
custom_registry="$SANDBOX/custom registry"
xdg_config="$SANDBOX/xdg config"
for mapping_root in "$default_registry" "$custom_registry" "$xdg_config/agents/my-repo-skills/skills"; do
  mkdir -p "$mapping_root/github.com/acme/widget"
done

for entry_point in command initializer; do
  for setting in unset empty custom; do
    default_repo="$SANDBOX/$entry_point-$setting"
    new_repo "$default_repo" "https://github.com/acme/widget.git"
    expected_registry="$default_registry"
    [[ "$setting" == custom ]] && expected_registry="$custom_registry"
    (
      export HOME="$test_home" XDG_CONFIG_HOME="$xdg_config"
      case "$setting" in
        unset) unset MY_REPO_SKILLS_DIR ;;
        empty) export MY_REPO_SKILLS_DIR="" ;;
        custom) export MY_REPO_SKILLS_DIR="$custom_registry" ;;
      esac
      if [[ "$entry_point" == command ]]; then
        "$RECONCILE" --quiet --cwd "$default_repo"
      else
        zsh -f -c 'cd "$1"; source "$2"; [[ "$MY_REPO_SKILLS_DIR" == "$3" ]]' -- \
          "$default_repo" "$ROOT/zsh/my-repo-skills-reconcile.zsh" "$expected_registry"
      fi
    )
    for adapter in .agents .claude; do
      assert test "$(readlink "$default_repo/$adapter/skills/_my-repo-skills")" = "$expected_registry/github.com/acme/widget"
    done
    assert test -z "$(git -C "$default_repo" status --porcelain)"
    pass "$entry_point uses the expected registry with $setting override and ignores XDG_CONFIG_HOME"
  done
done

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
print 'obsolete directory content' > "$collision/.agents/skills/_my-repo-skills/old"
mkdir -p "$collision/.claude/skills"
print 'obsolete file' > "$collision/.claude/skills/_my-repo-skills"
print 'keep sibling' > "$collision/.agents/skills/other-skill"
MY_REPO_SKILLS_DIR="$registry" "$RECONCILE" --quiet --cwd "$collision"
for adapter in .agents .claude; do
  assert test "$(readlink "$collision/$adapter/skills/_my-repo-skills")" = "$target"
done
assert test -f "$collision/.agents/skills/other-skill"
pass "files and directories at reserved adapter paths are replaced"

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

replacement="$SANDBOX/replacement"
new_repo "$replacement" "https://github.com/acme/widget.git"
mkdir -p "$replacement/.agents/skills" "$replacement/.claude/skills" "$SANDBOX/unrelated"
print 'keep me' > "$SANDBOX/unrelated/content"
ln -s "$SANDBOX/missing-old-registry/github.com/acme/widget" "$replacement/.agents/skills/_my-repo-skills"
ln -s "$SANDBOX/unrelated" "$replacement/.claude/skills/_my-repo-skills"
MY_REPO_SKILLS_DIR="$registry" "$RECONCILE" --quiet --cwd "$replacement"
for adapter in .agents .claude; do
  assert test "$(readlink "$replacement/$adapter/skills/_my-repo-skills")" = "$target"
done
assert test -f "$SANDBOX/unrelated/content"
assert test -z "$(git -C "$replacement" status --porcelain)"
MY_REPO_SKILLS_DIR="$registry" "$RECONCILE" --quiet --cwd "$replacement"
pass "wrong adapter symlinks are replaced without changing their former targets"

unlink "$replacement/.agents/skills/_my-repo-skills"
ln -s "$SANDBOX/unrelated" "$replacement/.agents/skills/_my-repo-skills"
git -C "$replacement" remote add upstream 'https://gitlab.com/acme/widget.git'
if MY_REPO_SKILLS_DIR="$registry" "$RECONCILE" --quiet --cwd "$replacement" 2>"$SANDBOX/error"; then
  print -u2 'not ok - ambiguous replacement should fail'
  exit 1
fi
assert grep -q 'multiple skill directories match' "$SANDBOX/error"
assert test "$(readlink "$replacement/.agents/skills/_my-repo-skills")" = "$SANDBOX/unrelated"
git -C "$replacement" remote remove upstream
pass "ambiguous mappings fail before adapter replacement"

MY_REPO_SKILLS_DIR="$SANDBOX/missing-registry" "$RECONCILE" --quiet --cwd "$replacement"
assert test "$(readlink "$replacement/.agents/skills/_my-repo-skills")" = "$SANDBOX/unrelated"
pass "a missing replacement leaves an unrelated adapter unchanged"

MY_REPO_SKILLS_DIR="$registry" zsh -f -c 'cd "$1"; source "$2"' -- "$replacement" "$ROOT/zsh/my-repo-skills-reconcile.zsh"
assert test "$(readlink "$replacement/.agents/skills/_my-repo-skills")" = "$target"
pass "the shell startup hook replaces wrong adapter symlinks"

rm -rf "$target"
MY_REPO_SKILLS_DIR="$registry" "$RECONCILE" --quiet --cwd "$repo"
assert test ! -L "$repo/.agents/skills/_my-repo-skills"
assert test ! -L "$repo/.claude/skills/_my-repo-skills"
pass "stale managed adapters are removed"

print "1..$passed"
