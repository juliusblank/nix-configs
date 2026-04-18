# .github/ — GitHub Actions (YAML) conventions

This directory contains CI/CD workflow definitions for the nix-configs repository.

## Formatting

- Indentation: 2 spaces
- Max line length: 100 characters
- No trailing whitespace

## Doc comments

- Each workflow file must open with a `#` comment block stating its trigger and purpose
- Non-obvious steps must have a `#` comment explaining *why*, not *what*

```yaml
# CI — runs nix flake check and builds the active host config on every PR and push to main.
name: CI
```

## Conventions

- Job IDs and step IDs use `kebab-case`
- Step `name` values are written as imperative sentences ("Build serenity", not "Building serenity")
- Pin all third-party actions to an exact tag (`actions/checkout@v4`, not `@main` or `@latest`)
- Secrets are referenced via `${{ secrets.NAME }}` — never echoed or logged
- OIDC-based AWS auth is preferred over long-lived key secrets
