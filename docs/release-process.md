# Release Process

Infrastructure point releases are explicit checkpoints on the `indev` branch. They document progression with `CHANGELOG.md` entries and annotated Git tags.

## Versioning

Use SemVer-style tags in the form `vMAJOR.MINOR.PATCH`.

- Patch releases document small fixes, dependency bumps, and docs-only progression.
- Minor releases document new hosts, services, profiles, or operational capabilities.
- Release branches are not used. `indev` remains the release source of truth.

The first release under this point-release policy is `v0.1.0`.

## Creating A Release

1. Update `CHANGELOG.md` so the release has a dated heading:

   ```markdown
   ## [v0.1.0] - 2026-06-19
   ```

2. Commit the release notes and implementation changes on `indev`.
3. On `devenv`, run a dry release validation:

   ```bash
   releaseInfra v0.1.0 --dry-run
   ```

4. Create the local annotated tag:

   ```bash
   releaseInfra v0.1.0
   ```

5. Push the branch and tag when ready:

   ```bash
   git push origin indev
   git push origin refs/tags/v0.1.0
   ```

Or create and push in one step:

```bash
releaseInfra v0.1.0 --push
```

## Validation

`releaseInfra` requires a clean `indev` checkout, rejects existing local or remote tags, checks for the matching `CHANGELOG.md` heading, and runs:

```bash
jq empty renovate.json
nix flake show path:. --no-write-lock-file
nix build --no-write-lock-file --no-link path:.#nixosConfigurations.<host>.config.system.build.toplevel
bash -n hosts/devenv/tools/update-network-firewall-rules.sh
bash -n hosts/devenv/tools/release-infra.sh
```

The build covers every host exported by the flake and present in the mesh topology.
