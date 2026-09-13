# Git Commit Style & Operational Safety Guidelines

## Operational Safety: No Unsolicited Commits or Pushes

- **Strict Prohibition on Unsolicited Commits & Pushes**:
  - Agents MUST NEVER execute `git commit`, `git push`, or modify branches/tags unless EXPLICITLY instructed by the user (e.g. "commit these changes", "push code to repo").
  - Autonomous workflows (implementing features, refactoring, fixing bugs, creating/updating agent rules or configurations) must NEVER trigger commits proactively.
  - All workspace modifications remain in working tree status for user review until an explicit commit command is provided.

---

## Git Commit Style

Always follow this commit message format and guidelines when explicitly asked to make commits:

### Commit Types (Choose 1)
- `feat(scope)`: User-facing change (new feature)
- `fix(scope)`: User-facing bug fix
- `perf(scope)`: User-facing performance improvement
- `chore(scope)`: Internal / build / tooling
- `refactor(scope)`: Code structure, no user change
- `ci(scope)`: Workflow / github actions
- `docs(scope)`: Documentation only
- `test(scope)`: Tests only

### Format
```
<type>(<scope>): <user-facing summary>

<developer-facing details>
```

### Rules
- **Subject**: For the user, used for Sparkle changelog.
- **Body**: For the developer, explaining what and why.
- **No Class/Function Names**: Do not mention classes or functions in the subject line.
- **Sparkle Changelog**: Only `feat`, `fix`, and `perf` types appear in the Sparkle changelog.
