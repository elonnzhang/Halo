# Halo — Release Checklist

Workflow for cutting a public release (Developer ID signed, notarized, stapled, Gatekeeper-clean).

## One-time setup

1. **Paid Apple Developer membership** — needed to issue Developer ID certificates.
2. **Generate a "Developer ID Application" certificate** in [developer.apple.com → Certificates](https://developer.apple.com/account/resources/certificates/list) and install it into the login keychain. Confirm with:
   ```sh
   security find-identity -p codesigning -v | grep "Developer ID Application"
   ```
3. **Create an app-specific password** for notarization at [appleid.apple.com → Sign-In and Security](https://appleid.apple.com/account/manage). Halo doesn't use Apple ID auth at runtime; this password is only used by `notarytool` to talk to Apple's notary service.
4. **Store the notarytool credentials** in the keychain so subsequent runs don't prompt:
   ```sh
   xcrun notarytool store-credentials halo-notary \
       --apple-id   "you@example.com" \
       --team-id    "ABCDE12345" \
       --password   "xxxx-xxxx-xxxx-xxxx"
   ```
5. **Export the signing identity** in your shell profile (or `.envrc` / `.env.release`):
   ```sh
   export HALO_SIGNING_IDENTITY="Developer ID Application: Your Name (ABCDE12345)"
   export HALO_NOTARY_PROFILE="halo-notary"   # defaults to halo-notary
   ```

## Per-release flow

### 1. Bump version

Edit `Resources/Info.plist`:
- `CFBundleShortVersionString` — semantic version, e.g. `1.1.2`.
- `CFBundleVersion` — monotonic build number; increment.

Re-run `swift test` to confirm nothing depends on the version string.

### 2. Refresh CHANGELOG

Move the **Unreleased** heading to today's date. List every notable user-visible change since the previous tag. The audit tooling expects:

```
## [<version>] — YYYY-MM-DD

### <Section>

- bullet
```

### 3. Tag the commit

```sh
git tag -s vX.Y.Z -m "Halo vX.Y.Z"   # or unsigned: git tag vX.Y.Z
git push origin main vX.Y.Z
```

### 4. Build + notarize

```sh
make release
```

This runs `clean → test → app → notarize` in order. Notarization typically takes 2–10 minutes; `notarytool submit --wait` blocks until Apple returns `Accepted` or `Invalid`.

Outputs land in `dist/`:
- `Halo.app` — stapled, Developer-ID-signed.
- `Halo-vX.Y.Z.zip` — flat archive ready to upload.
- `Halo-vX.Y.Z.zip.sha256` — release-notes-quotable checksum.

### 5. Gatekeeper sanity (post-build)

```sh
spctl --assess --verbose=2 --type execute dist/Halo.app
# expected: "dist/Halo.app: accepted"
```

If it says `rejected`, `notarize.sh` should have aborted; double-check that:
- `codesign -dv dist/Halo.app` shows your Developer ID authority, not `adhoc`.
- `xcrun stapler validate dist/Halo.app` reports a stapled ticket.

### 6. Upload + GitHub release

1. Upload `Halo-vX.Y.Z.zip` to the GitHub release for the tag.
2. Paste the SHA-256 from `Halo-vX.Y.Z.zip.sha256` into the release notes.
3. Quote the relevant CHANGELOG section in the release body.

### 7. Verify the published download

On a fresh user account (or quarantined download path):

```sh
# Simulate Gatekeeper's first-launch check on a downloaded zip
xattr -p com.apple.quarantine Halo-vX.Y.Z.zip   # should print a quarantine attr
ditto -x -k Halo-vX.Y.Z.zip /tmp/halo-verify/
spctl --assess --verbose=2 --type execute /tmp/halo-verify/Halo.app
```

Expected: `accepted` with `source=Notarized Developer ID`.

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `codesign` says `errSecInternalComponent` | Login keychain locked | `security unlock-keychain login.keychain-db` |
| `notarytool: Invalid` | Hardened runtime missing / unsigned helper | `xcrun notarytool log <submission-id> --keychain-profile halo-notary` to see Apple's reasons |
| `notarytool: Unauthorized` | App-specific password revoked | Regenerate at appleid.apple.com → re-`store-credentials` |
| `spctl: rejected` after `stapler validate` succeeded | Stale Gatekeeper cache | `sudo spctl --master-disable && sudo spctl --master-enable` to refresh |
| `make release` complains about missing `HALO_SIGNING_IDENTITY` | Env var not exported in current shell | Source your `.envrc` / `.env.release` or set inline |

## Ad-hoc / personal builds

Skip notarization entirely:

```sh
unset HALO_SIGNING_IDENTITY
make app       # ad-hoc signed, Gatekeeper will warn on first open
make install   # /Applications
```

This is fine for personal testing. Do **not** distribute ad-hoc-signed zips publicly — Gatekeeper will block them with `App is damaged` on the recipient's machine.
