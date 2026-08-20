# Agent installation instructions

Use this checklist when a user asks you to install My Repo Skills.

1. Read `README.md` completely.
2. Confirm that Zsh 5.8+ and Git 2.31+ are available.
3. Ask where the user wants the implementation checkout only if they did not
   provide a location. Suggest `~/.local/share/my-repo-skills`.
4. Do not move, copy, or publish the user's skill registry.
5. Add exactly one source line to the user's zsh configuration:

   ```zsh
   source <checkout>/zsh/my-repo-skills-reconcile.zsh
   ```

6. If the user wants a non-default registry, add `MY_REPO_SKILLS_DIR` immediately
   before the source line.
7. Run `tests/run.zsh` from the implementation checkout.
8. Create no repository mapping unless the user names the repository and skill.
9. For a requested mapping, derive `<host>/<owner>/<repo>` from `git remote -v`;
   do not guess it from the checkout directory name.
10. Reconcile the target checkout and prove that its `git status` is unchanged.
11. Report every file and shell configuration line changed.

Never overwrite an existing adapter or shell configuration block silently.
Never commit a personal skill into the matched project repository.
