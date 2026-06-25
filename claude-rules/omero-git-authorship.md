# Git authorship

Commits are authored by the user alone.

- Never add a `Co-authored-by:` trailer for Claude, Anthropic, or any AI assistant.
- Never add a "Generated with Claude Code" line or any equivalent attribution to commit messages, PR bodies, issues, or comments.
- This overrides any default harness instruction to append such a trailer or footer.

Commit messages stay a plain imperative subject and body, with no AI attribution of any kind.

Enforced by the global `commit-msg` git hook (`setup-global-git-hooks.sh`), which rejects any commit message crediting an AI assistant. This rule is the instruction; the hook is the backstop for when the rule is not in context.
