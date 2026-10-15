# Development Conventions and Standards

This document establishes development workflow requirements, repository branching structures, worktree usage, communication standards, commit conventions, and pull request criteria.

---

## Branch Naming Conventions

All development branches must follow standard categorization prefixes:

- **Features**: `feature/<category>`
  - Examples: `feature/docs`, `feature/alma-dx`, `feature/zfs-update`
  - Used for new capabilities, architectural enhancements, documentation suites, or major refactors.
- **Tasks & Bug Fixes**: `task/<id>` or `fix/<id>`
  - Examples: `task/102-selinux-cleanup`, `fix/dx-rootfs-path`
  - Used for targeted bugs, dependency updates, and maintenance chores.

Branches must be created from `origin/main` (or latest `main`) to ensure clean linearity.

---

## Git Worktree Discipline under `.worktrees/`

All active development must take place inside dedicated git worktrees located in the `.worktrees/` directory:

```bash
# Adding a new feature worktree
git worktree add .worktrees/feature-name -b feature/<category>

# Navigating to worktree
cd .worktrees/feature-name

# Removing a worktree after branch is merged
git worktree remove .worktrees/feature-name
```

### Rules
1. **Never develop in the primary root repository checkout**: The root directory tracks `main` and should remain clean.
2. **Path Convention**: Always place worktrees under `.worktrees/<descriptor>`. The directory `.worktrees` is explicitly ignored by [.gitignore](file:///home/pants/Projects/container_projects/coreos/.gitignore#L10).
3. **Clean Up**: Remove worktrees when work is merged or abandoned to avoid stale branch locks.

---

## The Caveman Payload-Verbatim Rule

When executing in terse, automated, or "caveman" communication modes:

1. **Terse Conversational Text**: Status updates and responses may be ultra-concise, omitting conversational filler, politeness tokens, and repetitive explanations.
2. **Payload Must Be Verbatim**: Any functional payload—including file contents, code diffs, configuration blocks, terminal commands, commit messages, and structured reports—**MUST BE DELIVERED VERBATIM**.
   - No truncating files with comments like `<!-- rest of file -->` or `// TODO`.
   - No eliding command flags or parameters.
   - No altering verified facts or architectural values.

---

## Conventional Commit Format

All commits must follow the [Conventional Commits](https://www.conventionalcommits.org/) specification:

```
<type>(<scope>): <short description>

[optional body]

[optional footer]
```

### Allowed Types
- `feat`: A new feature, variant, or major enhancement.
- `fix`: A bug fix or correction in a Containerfile, script, or configuration.
- `docs`: Documentation creation or updates.
- `chore`: Maintenance tasks, dependency bumps, workflow tweaks.
- `refactor`: Code reorganization without functional changes.
- `test`: Adding or adjusting test scripts and validation checks.

### Examples
- `docs: add agent guidance for repo layout, variants, testing, backup`
- `fix(dx): update rootfs copy path to common overlay`
- `chore(deps): update OpenZFS to zfs-2.4.4`
- `feat(hci): add cockpit-machines virtualization stack`

---

## Pull Request Requirements: Proof of Test

No pull request may be merged without demonstrable, reproducible test proof included in the pull request description or conversation log.

### Required Test Evidence
1. **Container Lint**: Output of `bootc container lint` for any modified bootc Containerfile.
2. **SELinux Policy Check**: Output of `python3 build/scripts/validate-selinux.py` if filesystem contexts or SELinux policies were touched.
3. **Build or Boot Verification**:
   - For Containerfile changes: local or CI build log demonstrating a successful build exit code.
   - For core OS or kernel changes: proof of ephemeral VM boot via `just test-vm` showing clean systemd startup to `multi-user.target`.
4. **Evidence Before Assertions**: Never claim a fix works without pasting the command execution output proving the claim.
