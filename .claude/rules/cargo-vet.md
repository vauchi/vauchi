---
paths:
  - "**/supply-chain/**"
  - "**/cargo-vet*"
---

## Cargo Vet (MANDATORY)

### No AI-Generated Audits

- **NEVER add `[[audits.*]]` entries** to any `supply-chain/audits.toml` file
- Audits are attestations that a human reviewed the code — AI cannot make that claim
- When cargo-vet fails due to unvetted dependencies, **add or bump `[[exemptions.*]]`** entries in `supply-chain/config.toml` instead
- `[[trusted.*]]` entries (publisher trust) are fine to add or update

### Workflow

1. Run `cargo vet` to identify unvetted deps
2. Add/update `[[exemptions.crate_name]]` with the required version in `config.toml`
3. Run `cargo vet fmt` to ensure correct ordering
4. Verify with `cargo vet` again

### Pre-Push Hook

The pre-push hook temporarily removes `.cargo/config.toml` (path overrides) and runs
`cargo vet --locked` against the git-resolved lockfile. This means exemptions must cover
both the local (path-override) version AND the remote (git-resolved) version of deps.
When in doubt, add exemptions for both versions.
