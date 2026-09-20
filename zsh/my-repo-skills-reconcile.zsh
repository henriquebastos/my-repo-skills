# Source this file from .zshrc to enable my-repo-skills.

emulate -L zsh

local source_file="${${(%):-%N}:A}"
typeset -g MY_REPO_SKILLS_HOME="${source_file:h:h}"
typeset -gx MY_REPO_SKILLS_DIR="${MY_REPO_SKILLS_DIR:-$HOME/.agents/my-repo-skills/skills}"
typeset -gaU path
path=("$MY_REPO_SKILLS_HOME/bin" $path)

typeset -g __my_repo_skills_worktree=""
__reconcile_my_repo_skills() {
  local candidate="$PWD"

  while [[ "$candidate" != "/" && ! -e "$candidate/.git" ]]; do
    candidate="${candidate:h}"
  done
  if [[ ! -e "$candidate/.git" ]]; then
    __my_repo_skills_worktree=""
    return 0
  fi
  [[ "$candidate" == "$__my_repo_skills_worktree" ]] && return 0

  my-repo-skills-reconcile --quiet --cwd "$candidate" || return
  __my_repo_skills_worktree="$candidate"
}

autoload -Uz add-zsh-hook
add-zsh-hook -d chpwd __reconcile_my_repo_skills 2>/dev/null || true
add-zsh-hook chpwd __reconcile_my_repo_skills
__reconcile_my_repo_skills
