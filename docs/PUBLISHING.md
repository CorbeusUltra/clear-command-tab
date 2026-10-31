# Publishing and privacy

## Existing public repository

The public repository is [CorbeusUltra/clear-command-tab](https://github.com/CorbeusUltra/clear-command-tab). Updates can be committed and pushed to its existing history after reviewing their contents and commit identity.

Older commits are already public and contain machine-specific paths and author metadata. Updating files, changing the Git identity or adding ignore rules does not remove those records. Rewriting history is a separate decision and cannot remove copies or forks outside the repository.

For future commits, configure the Git author name and email you intend to expose; a GitHub-provided no-reply email can protect a personal email address. Review the staged changes before publishing. GitHub account settings can also block certain command-line pushes that expose a private email address.

## Optional curated export

`scripts/export-source.py` can create a history-free source copy for review or distribution. Its allowlist includes source, selected artwork, build/test scripts, example configuration, licence and documentation. It excludes Git history, personal configuration, raw diagnostics, local snapshots and abandoned design proposals. The export includes a SHA-256 manifest; its output under `.dist/` is a local deliverable, not a file to commit. The exporter does not create a remote or push changes.

## What stays local

| Material | Location / pattern | Reason |
| --- | --- | --- |
| Personal build/signing configuration | `.local/build.env`, `.env*` except example templates | Local certificate selection, local destinations and potentially environment secrets |
| Private notes and retained snapshots | `.local/history/`, `.local/parked/` | Earlier machine-specific documents and pre-retirement source snapshots |
| Raw measurements, renders, fixture apps and builds | `.build/`, `*.app/`, `*.dSYM/`, `*.log` | Generated output; raw diagnostics may include app/window metadata and local paths |
| Prepared source exports | `.dist/` | Generated deliverables; no need to commit archives or duplicate source trees |
| Local assistant/editor instructions | `AGENTS.md`, `.agents/`, `.codex/`, `.vscode/`, `.idea/` | Personal development workflow; not required to build the public project |
| Signing keys/certificates and provisioning files | `*.p12`, `*.pfx`, `*.pem`, `*.key`, `*.p8`, `*.cer`, provisioning profiles | Never bundle personal signing material with source |
| Superseded logo proposals and their dedicated generator | `Design/LogoProposals/`, `Design/DarkLogoProposals/`, `Design/MonochromeProposal/`, `scripts/make-logo-proposals.swift` | Unused design experiments; local notes may contain personal paths |

The certificate identifier formerly stored in the signing script is not a private key, but identifies a personal development configuration. The current script reads it from ignored configuration. The private signing key remains in the local keychain and is not part of the source export.

## What remains public

Keep `Package.swift`, `Sources/`, `Resources/`, `Tests/`, the maintained `scripts/`, `config/build.env.example`, `Design/SelectedLogo/`, README/change/validation documents, and `docs/`. Keep `LICENSE`, `THIRD_PARTY_NOTICES.md` and upstream licence texts. These are required source, reusable project assets or documentation; they are not personal backups.

The current bundle/runtime identifier is `io.github.corbeusultra.ClearCommandTab`, based on the public GitHub handle. Earlier public history also contains the previous identity. The current identifier is not a secret or signing credential; see [application identity](APPLICATION_IDENTITY.md). The public GitHub handle and third-party copyright notices also remain.

## Verify the actual commit contents

Ignore rules apply to untracked files. A file already present in Git's index remains eligible for a commit until it is removed from the index; its working copy can be retained. Review the staged content as well as the working tree. Staging an older version can preserve private text even after the on-disk file is cleaned.

Review the exporter manifest and staged file list before publication. The publication checks are a targeted review of known paths, signing identifiers and common credential markers, not a guarantee that every possible secret has been detected. Never add private files with `git add -f` merely to bypass an ignore rule.
