# Hooks

## pre-commit (git identity guard)

Refuses any commit whose author email is not on the allowlist, so the build loop's
commits always attribute to the right GitHub account. This is the per-commit half of
the identity defence; the setup gate is the other half (it blocks the loop from
starting in a repo with the wrong identity).

Install into a repo:

    cp hooks/pre-commit <repo>/.git/hooks/pre-commit
    chmod +x <repo>/.git/hooks/pre-commit

Install for all future repos (template):

    mkdir -p ~/.git-template/hooks
    cp hooks/pre-commit ~/.git-template/hooks/pre-commit
    chmod +x ~/.git-template/hooks/pre-commit
    git config --global init.templatedir ~/.git-template

Override the allowlist per machine:

    export GIT_IDENTITY_ALLOWLIST="you@example.com you@users.noreply.github.com"
