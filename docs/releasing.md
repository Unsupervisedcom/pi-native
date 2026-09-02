# Releasing PiNative

Official PiNative releases are Developer ID signed, notarized by Apple,
stapled, Gatekeeper-assessed, and published as a **draft** GitHub Release for
maintainer review.

The release workflow never accepts unsigned artifacts and does not publish a
release if signing, notarization, stapling, or verification fails.

## One-time Apple setup

### 1. Create a Developer ID Application certificate

In [Apple Developer Certificates, Identifiers & Profiles](https://developer.apple.com/account/resources/certificates/list):

1. Select the Apple Developer team that owns the release.
2. Select **Certificates**, then **+**.
3. Choose **Developer ID Application**.
4. Create a certificate signing request in Keychain Access:
   **Keychain Access → Certificate Assistant → Request a Certificate From a
   Certificate Authority**, save the request to disk, and upload it to Apple.
5. Download and open the issued certificate to install it in Keychain Access.
6. Export its certificate and private key together as a password-protected
   `.p12` file. Keep both the file and its password out of git and chat.

The app’s permanent bundle identifier is `com.unsupervised.PiNative`.

### 2. Create a notary-service API key

In [App Store Connect](https://appstoreconnect.apple.com/):

1. Open **Users and Access → Integrations → Keys**.
2. Generate a team API key with permission to submit notarization requests
   (the **Developer** role or a more privileged role).
3. Download the `.p8` private key immediately; Apple does not offer a second
   download.
4. Record its Key ID and the team’s Issuer ID.

Use a dedicated key for this automation, limit who can manage it, and revoke it
when access is no longer required.

## GitHub Actions configuration

Create a GitHub Actions environment named `release`. The official release job
declares this environment so signing and notarization credentials are unavailable
to pull-request and routine CI jobs. Restrict the environment to protected release
tags matching `v*`; optionally require maintainer approval before deployment.

Add the following **Actions repository variable**. It identifies the signing
team and is not confidential, but keeping it out of the repository lets a fork
or new maintainer configure its own release identity.

| Variable | Value |
| --- | --- |
| `APPLE_TEAM_ID` | Apple Team ID that owns the Developer ID certificate. |

Add the following **environment secrets** to the `release` environment. Never add
their values to tracked files, workflow logs, issue comments, or release notes.

| Secret | Value |
| --- | --- |
| `APPLE_DEVELOPER_ID_CERTIFICATE_P12_BASE64` | Base64 encoding of the Developer ID `.p12` file. |
| `APPLE_DEVELOPER_ID_CERTIFICATE_PASSWORD` | Password used when exporting that `.p12`. |
| `APPLE_NOTARY_API_KEY_ID` | App Store Connect API Key ID. |
| `APPLE_NOTARY_API_ISSUER_ID` | App Store Connect API Issuer ID. |
| `APPLE_NOTARY_API_KEY_P8_BASE64` | Base64 encoding of the downloaded `.p8` private key. |
| `POSTHOG_PROJECT_API_KEY` | PostHog `phc_` project token used by official builds for opt-in product analytics. |

The workflow generates a fresh high-entropy password for its temporary keychain
during every run; no keychain-password secret is stored.

On macOS, copy a file’s Base64 value without saving another credential file:

```sh
base64 < DeveloperIDApplication.p12 | pbcopy
base64 < AuthKey_ABC123DEFG.p8 | pbcopy
```

For a local official release, set `APPLE_TEAM_ID` in the command environment.
The release script stops before signing if it is absent.

## Local official-release verification

After installing the Developer ID certificate and creating a local notarytool
profile, run:

```sh
xcrun notarytool store-credentials pinative-notary \
  --key /secure/path/AuthKey_ABC123DEFG.p8 \
  --key-id ABC123DEFG \
  --issuer 00000000-0000-0000-0000-000000000000

APPLE_TEAM_ID=YOUR_APPLE_TEAM_ID \
  scripts/build-release-dmg.sh --official 0.1.0 \
    --build-number 1 \
    --notary-profile pinative-notary
```

The script produces:

```text
dist/PiNative-0.1.0.dmg
dist/PiNative-0.1.0.dmg.sha256
```

It verifies the exported app signature, signs the DMG, waits for notarization,
staples and validates the ticket, performs `spctl` assessment, and verifies the
app signature inside the final DMG. Do not upload the resulting artifact
manually; use the tagged workflow so Releases contain only CI-built artifacts.

## Publishing a release

1. Complete the local verification above at least once after credential setup.
2. Protect `v*` tags in GitHub so only authorized maintainers can create them.
3. Merge the intended release commit to `main` and make sure the working tree
   is clean.
4. Create and push a semantic-version tag, for example:

   ```sh
   git tag v0.1.0
   git push origin v0.1.0
   ```

5. The **Official Release DMG** workflow creates
   `PiNative-0.1.0.dmg` and its SHA-256 checksum, then creates a draft GitHub
   Release.
6. Review the workflow logs and draft assets. Download the DMG through a
   browser on a clean macOS user account, drag the app into Applications, and
   launch it before publishing the draft.
7. Confirm the notes state macOS 14+, the external Pi prerequisite, and normal
   macOS permission prompts. Never advise users to disable Gatekeeper.
8. Publish the draft only after that manual install test succeeds.

If notarization fails, inspect the `notarytool` log from the failed job, correct
the problem, and create a new patch tag. Do not replace an already-public
release tag.
