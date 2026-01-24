# GitLab ↔ GitHub Bridge

This document explains how Vauchi maintains repositories on both GitLab (primary) and GitHub (mirror), and how to update authentication tokens.

## Overview

```
┌─────────────┐         ┌─────────────┐
│   GitLab    │ ──────► │   GitHub    │
│  (primary)  │  mirror │  (public)   │
└──────┬──────┘         └─────────────┘
       │
       ▼
┌─────────────┐
│  Container  │
│  Registry   │
└─────────────┘
```

- **GitLab**: Primary development, CI/CD, container registry
- **GitHub**: Public mirror for community visibility, sponsors, issues

## Visibility Policy

**Rule**: Repos with `_` prefix in local directory are **private** (GitLab only). All others are **public** and mirrored to GitHub.

| Local Prefix | GitLab Visibility | GitHub Mirror |
|--------------|-------------------|---------------|
| `_docs/`, `_assets/`, etc. | Private | No |
| `core/`, `cli/`, etc. | Public | Yes |

## Repository Mapping

### Public Repos (GitLab + GitHub)

| GitLab | GitHub | Purpose |
|--------|--------|---------|
| `vauchi/vauchi` | `vauchi/vauchi` | Main monorepo |
| `vauchi/core` | `vauchi/core` | Core library + mobile bindings |
| `vauchi/cli` | `vauchi/cli` | Command-line interface |
| `vauchi/tui` | `vauchi/tui` | Terminal UI |
| `vauchi/desktop` | `vauchi/desktop` | Tauri + SolidJS desktop app |
| `vauchi/relay` | `vauchi/relay` | WebSocket relay server |
| `vauchi/e2e` | `vauchi/e2e` | End-to-end tests |
| `vauchi/features` | `vauchi/features` | Gherkin specs (mirror pending) |
| `vauchi/android` | `vauchi/android` | Kotlin/Compose app |
| `vauchi/ios` | `vauchi/ios` | SwiftUI app |
| `vauchi/vauchi-mobile-android` | `vauchi/vauchi-mobile-android` | Android bindings |
| `vauchi/vauchi-mobile-swift` | `vauchi/vauchi-mobile-swift` | Swift bindings |

### Private Repos (GitLab only)

| GitLab | Local Dir | Purpose |
|--------|-----------|---------|
| `vauchi/docs` | `_docs/` | Documentation |
| `vauchi/assets` | `_assets/` | Brand assets |
| `vauchi/dev-tools` | `_dev-tools/` | Dev scripts |
| `vauchi/infra` | `_infra/` | Infrastructure |
| `vauchi/strategy` | `_strategy/` | Business strategy |
| `vauchi/website` | `_website/` | Landing page |

## Local Git Configuration

Each repo has two remotes:

```bash
# Check remotes
git remote -v

# Typical output:
# origin    git@gitlab.com:vauchi/vauchi.git (fetch/push)
# github    git@github.com:vauchi/vauchi.git (fetch/push)
```

### Push to Both

```bash
# Push to GitLab (default)
git push origin main

# Push to GitHub
git push github main

# Push to both
git push origin main && git push github main
```

## Container Registry

Vauchi uses **GitLab Container Registry** for Docker images:

```
registry.gitlab.com/vauchi/relay/vauchi-relay:tag
registry.gitlab.com/vauchi/website/vauchi-landing:tag
```

### Authentication

Kamal deployment requires a GitLab Personal Access Token (PAT) with `read_registry` and `write_registry` scopes.

**Token location**: `.kamal/secrets` (gitignored)

```bash
# .kamal/secrets
KAMAL_REGISTRY_PASSWORD=glpat-xxxxxxxxxxxxxxxxxxxx
```

## Updating the GitLab Registry Token

When you see this error during `kamal deploy`:

```
unauthorized: HTTP Basic: Access denied.
If a token was provided, it was either incorrect, expired, or improperly scoped.
```

### Step 1: Generate New Token

1. Go to GitLab: **Settings → Access Tokens** (or **User Settings → Personal Access Tokens** for user-level)
   - URL: https://gitlab.com/-/user_settings/personal_access_tokens

2. Create token with:
   - **Name**: `kamal-registry` (or descriptive name)
   - **Expiration**: Set reasonable expiry (e.g., 1 year)
   - **Scopes**:
     - `read_registry` ✓
     - `write_registry` ✓

3. Copy the token (starts with `glpat-`)

### Step 2: Update Local Secrets

```bash
# Edit the secrets file
nano ~/.kamal/secrets
# or
nano /home/megloff1/Workspace/vauchi/.kamal/secrets

# Update the line:
KAMAL_REGISTRY_PASSWORD=glpat-your-new-token-here
```

### Step 3: Verify

```bash
# Test registry login
docker login registry.gitlab.com -u gitlab-ci-token -p $(cat ~/.kamal/secrets | grep KAMAL_REGISTRY_PASSWORD | cut -d= -f2)

# Should output: Login Succeeded
```

### Step 4: Deploy

```bash
cd /home/megloff1/Workspace/vauchi
kamal deploy -c infra/config/deploy.yml
```

## GitHub Token (for GitHub Actions)

If using GitHub Actions for CI:

1. Go to: **Settings → Developer settings → Personal access tokens → Fine-grained tokens**
2. Create token with repository access
3. Add as repository secret: **Settings → Secrets → Actions**

## Mirroring Setup (Optional)

For automatic GitLab → GitHub mirroring:

### Option A: GitLab Push Mirror

1. GitLab repo → **Settings → Repository → Mirroring repositories**
2. Add mirror with these fields:
   - **Git repository URL**: `https://<github-username>@github.com/vauchi/vauchi.git`
     - Replace `<github-username>` with your GitHub username
   - **Mirror direction**: Push
   - **Authentication method**: Password
   - **Password**: Your GitHub Personal Access Token (PAT)
     - Generate at: GitHub → Settings → Developer settings → Personal access tokens → Tokens (classic)
     - Required scopes: `repo` (full control of private repositories)
   - **Only mirror protected branches**: Uncheck (unless you only want to mirror `main`)
3. Click **Mirror repository**
4. Click the refresh icon (🔄) to trigger initial sync

### Option B: Manual Push Script

```bash
#!/bin/bash
# scripts/push-all.sh
git push origin main
git push github main
echo "Pushed to both remotes"
```

## Troubleshooting

### "Access denied" on registry

1. Check token expiry on GitLab
2. Verify scopes include `read_registry` and `write_registry`
3. Ensure `.kamal/secrets` has correct format (no quotes around value)

### Push rejected to GitHub

```bash
# If GitHub is behind, force push (careful!)
git push github main --force

# Or fetch and merge first
git fetch github
git merge github/main
git push github main
```

### Container not found

```bash
# List available images
docker images | grep vauchi

# Pull latest from registry
docker pull registry.gitlab.com/vauchi/relay/vauchi-relay:latest
```

## Security Notes

- Never commit `.kamal/secrets` (it's gitignored)
- Rotate tokens periodically (recommended: every 6-12 months)
- Use fine-grained tokens with minimal scopes
- For CI/CD, use CI variables instead of personal tokens where possible
