# Git Commit Style Guidelines

## Git Commit Style
Always follow this commit message format and guidelines when making commits:

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
