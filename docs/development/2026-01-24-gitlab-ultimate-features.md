# GitLab Ultimate Features for Vauchi

We're part of the [GitLab for Open Source Program](https://about.gitlab.com/solutions/open-source/), which gives us free access to GitLab Ultimate features.

## What We Get

| Feature | Value | Status |
|---------|-------|--------|
| **Compute minutes** | 50,000/year | Available (we also use self-hosted runners) |
| **GitLab Ultimate** | Full tier | Available |
| **AI features** | GitLab Duo | Available |
| **Security scanning** | SAST, DAST, Dependency, Container | To enable |

## Security Scanning (Priority)

### SAST (Static Application Security Testing)

Scans source code for vulnerabilities on every commit.

**Enable in `.gitlab-ci.yml`:**
```yaml
include:
  - template: Security/SAST.gitlab-ci.yml

variables:
  SAST_EXCLUDED_PATHS: "target/, node_modules/, dist/"
```

**Languages supported:**
- Rust (via semgrep)
- TypeScript/JavaScript
- Kotlin
- Swift

### Dependency Scanning

Scans `Cargo.lock`, `package-lock.json` for vulnerable dependencies.

```yaml
include:
  - template: Security/Dependency-Scanning.gitlab-ci.yml
```

### Container Scanning

Scans Docker images for vulnerabilities (useful for relay deployment).

```yaml
include:
  - template: Security/Container-Scanning.gitlab-ci.yml

container_scanning:
  variables:
    CS_IMAGE: $CI_REGISTRY_IMAGE/vauchi-relay:$CI_COMMIT_SHA
```

### Secret Detection

Prevents accidental commit of tokens, keys, passwords.

```yaml
include:
  - template: Security/Secret-Detection.gitlab-ci.yml
```

## AI Features (GitLab Duo)

### Code Suggestions
- IDE integration for AI-powered code completion
- Works in VS Code with GitLab extension

### AI Chat
- Explain code
- Generate tests
- Refactoring suggestions

### Vulnerability Explanation
- AI explains security findings
- Suggests fixes
- False positive detection

## Recommended Setup

### Phase 1: Security Scanning (Do First)

Add to root `.gitlab-ci.yml`:

```yaml
include:
  - template: Security/SAST.gitlab-ci.yml
  - template: Security/Dependency-Scanning.gitlab-ci.yml
  - template: Security/Secret-Detection.gitlab-ci.yml

variables:
  SAST_EXCLUDED_PATHS: "target/, node_modules/, dist/, builds/, cache/"
  DS_EXCLUDED_PATHS: "target/, node_modules/, builds/"
```

### Phase 2: Container Scanning (For Relay)

Add to `relay/.gitlab-ci.yml`:

```yaml
include:
  - template: Security/Container-Scanning.gitlab-ci.yml
```

### Phase 3: Merge Request Approvals

Configure security policies:
1. Go to **Security & Compliance → Policies**
2. Create approval rule requiring security scan pass
3. Block merge if critical vulnerabilities found

### Phase 4: Vulnerability Dashboard

View all vulnerabilities across projects:
1. Go to **Security & Compliance → Vulnerability report**
2. Triage and assign vulnerabilities
3. Track remediation progress

## Best Practices

### Scan on Every MR
```yaml
sast:
  rules:
    - if: $CI_MERGE_REQUEST_IID
    - if: $CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH
```

### Fail on Critical Vulnerabilities
```yaml
sast:
  allow_failure: false
  variables:
    SAST_FAIL_LEVEL: critical
```

### Exclude False Positives
Create `.gitlab/sast-config.yml` to suppress known false positives.

## Sources

- [GitLab SAST Docs](https://docs.gitlab.com/user/application_security/sast/)
- [Dependency Scanning Docs](https://docs.gitlab.com/user/application_security/dependency_scanning/)
- [Container Scanning Docs](https://docs.gitlab.com/user/application_security/container_scanning/)
- [GitLab Duo Features](https://about.gitlab.com/gitlab-duo/)
