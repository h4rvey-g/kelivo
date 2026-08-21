# macOS automatic updates

Kelivo uses Sparkle 2 for macOS updates. The first Sparkle-enabled release must
still be installed manually. Releases after that can be downloaded, verified,
installed, and relaunched from inside the app.

## Signing key

Sparkle update signing uses a free Ed25519 key pair. The public key is embedded
in `macos/Runner/Info.plist`. The private key must never be committed.

The current private key is stored locally at:

```text
~/.config/kelivo/sparkle_ed25519_private_key
```

Back up this file in a secure credential store. Losing it prevents existing
installations from trusting future unsigned-by-the-old-key updates.

Configure the private key as a GitHub Actions repository secret:

```bash
gh secret set SPARKLE_PRIVATE_KEY \
  < ~/.config/kelivo/sparkle_ed25519_private_key
```

## Release flow

Use `.github/workflows/build-stable-44.yml` for releases that should be visible
to Sparkle. Its macOS job:

1. Builds a monotonically increasing `CFBundleVersion` from the semantic
   version in `pubspec.yaml`.
2. Creates the normal DMG for first-time installation.
3. Signs the DMG with `SPARKLE_PRIVATE_KEY` and generates `appcast.xml`.
4. Uploads both files to the GitHub Release.

The app reads the stable feed from:

```text
https://github.com/h4rvey-g/kelivo/releases/latest/download/appcast.xml
```

GitHub's `releases/latest` endpoint excludes prereleases, so the in-app stable
update check also ignores prerelease releases.

## Distribution limitation

This setup does not require a paid Apple Developer account. Sparkle verifies
the downloaded update with EdDSA, but the app itself is not Developer ID signed
or notarized. macOS may therefore show Gatekeeper warnings during the initial
manual installation. Developer ID signing and notarization can be added later
without replacing Sparkle.
