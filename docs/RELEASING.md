# Releasing ProcessLink

A GitHub Release carries both desktop installers:

| Asset | Built on | Notes |
|---|---|---|
| `ProcessLink-<version>-macOS-universal.dmg` | macOS runner | `.app` + `/Applications` link; arm64 + x86_64 |
| `ProcessLink_<version>_x64_en-US.msi` | Windows runner | per-machine MSI |
| `ProcessLink_<version>_x64-setup.exe` | Windows runner | NSIS installer |
| `SHA256SUMS.txt` | release job | verify every download |

The workflow is [`.github/workflows/release.yml`](../.github/workflows/release.yml).

The current release, [v0.1.58](https://github.com/pallefar/ProcessLink/releases/tag/v0.1.58),
was published with the macOS DMG and a locally cross-built Windows NSIS
installer because GitHub Actions is currently locked on the account with a
billing error. The workflow is ready to add the MSI and a CI-built NSIS
installer once Actions is available.

## Publish a release

```bash
git remote add origin git@github.com:<owner>/<repo>.git   # once
git push -u origin main

git tag v0.1.58
git push origin v0.1.58
```

The tag starts the workflow. It builds macOS and Windows in parallel, mounts
the DMG and runs the in-app self-test, then creates the GitHub Release with
the installers and checksums. You can also run **Actions → Release installers
→ Run workflow** and enter a version; it creates `v<version>` at the selected
commit.

## macOS signing

Without secrets the DMG is **ad-hoc signed** and not notarized. It runs from
Finder with right-click → Open, or after clearing quarantine:

```bash
xattr -dr com.apple.quarantine /Applications/ProcessLink.app
```

For a normal double-click install, add these repository secrets:

| Secret | Value |
|---|---|
| `MACOS_CERTIFICATE_P12` | base64 of the Developer ID Application `.p12` |
| `MACOS_CERTIFICATE_PASSWORD` | password for the `.p12` |
| `APPLE_ID` | Apple developer account |
| `APPLE_TEAM_ID` | 10-character team id |
| `APPLE_APP_SPECIFIC_PASSWORD` | app-specific password for notarytool |

The workflow imports the certificate, signs with hardened runtime and
timestamp, and passes `--notarize` when `APPLE_ID` is present. Verify with:

```bash
spctl --assess --type execute --verbose /Volumes/ProcessLink/ProcessLink.app
```

## Windows signing

The MSI/NSIS installers are unsigned unless a Windows code-signing certificate
is configured. Windows SmartScreen will warn on first run. Add the Tauri
`bundle.windows.certificateThumbprint` (or a custom `signCommand`) and the
certificate to the Windows runner before calling the build signed.

## Build locally

```bash
# macOS universal DMG (ad-hoc unless SIGN_IDENTITY is set)
macos/ProcessLink/tools/package.sh --version 0.1.58

# macOS notarized
SIGN_IDENTITY="Developer ID Application: …" \
APPLE_ID=… APPLE_TEAM_ID=… APPLE_APP_SPECIFIC_PASSWORD=… \
macos/ProcessLink/tools/package.sh --version 0.1.58 --notarize

# Windows, on a Windows host
npm ci --prefix web
npm install --prefix windows/ProcessLink.Windows
npm run build --prefix windows/ProcessLink.Windows
```

### Cross-build the Windows NSIS installer from macOS

The released Windows NSIS installer was built this way. It needs Rust,
`cargo-xwin`, LLVM's `llvm-rc` and `makensis`:

```bash
brew install llvm makensis
cargo install cargo-xwin --locked
npm --prefix web run build
windows/ProcessLink.Windows/tools/build-installer-macos.sh 0.1.0
```

The supported Windows path is still the `windows-latest` workflow, which also
produces the MSI. The cross-built NSIS installer is unsigned and was not run
on a Windows host in this environment; treat it as the fallback until the
Actions job is available.

Artifacts:

- macOS: `macos/ProcessLink/dist/`
- Windows (CI): `windows/ProcessLink.Windows/src-tauri/target/release/bundle/{msi,nsis}/`
- Windows (cross-build): `windows/ProcessLink.Windows/dist/`
