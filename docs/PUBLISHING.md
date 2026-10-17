# Publishing without private development history

## Start from the curated export

Use the history-free source export prepared by `scripts/export-source.py` as the public repository's starting folder. Its allowlist includes the source, selected artwork, build/test scripts, example configuration, licence and project documentation. It excludes Git history, personal configuration, raw diagnostics, local snapshots and abandoned design proposals.

The existing development repository deliberately keeps its local history. Older commits contain machine-specific paths, an author identity and a personal signing-certificate identifier. Updating files or adding ignore rules does not remove those records. Do not publish that existing history if these details should remain private. The public repository should start with a new history created from the export. No remote or publication is created by the exporter.

The export includes a SHA-256 manifest for reviewing its contents. The folder and archive under `.dist/` are local deliverables, not files to commit back into the development repository. Before initializing the public repository, configure the Git author name and email you want to expose; use your GitHub-provided no-reply email if desired. The new history's author identity is separate from the application author credit.

## What stays local

| Material | Location / pattern | Reason |
| --- | --- | --- |
| Personal build/signing configuration | `.local/build.env`, `.env*` except example templates | Local certificate selection, local destinations and potentially environment secrets |
| Private notes and retained snapshots | `.local/history/`, `.local/parked/` | Earlier machine-specific documents and pre-retirement source snapshots |
| Raw measurements, renders, fixture apps and builds | `.build/`, `*.app/`, `*.dSYM/`, `*.log` | Generated output; raw diagnostics may include app/window metadata and local paths |
| Prepared source exports | `.dist/` | Generated deliverables; no need to commit archives or duplicate source trees |
| Local assistant/editor instructions | `AGENTS.md`, `.agents/`, `.codex/`, `.vscode/`, `.idea/` | Personal development workflow; not required to build the public project |
| Signing keys/certificates and provisioning files | `*.p12`, `*.pfx`, `*.pem`, `*.key`, `*.p8`, `*.cer`, provisioning profiles | Never bundle personal signing material with source |
| Superseded logo proposals and their dedicated generator | `Design/LogoProposals/`, `Design/DarkLogoProposals/`, `scripts/make-logo-proposals.swift` | Not secrets; excluded because they are unused design experiments |

The certificate identifier formerly stored in the signing script is not a private key, but identifies a personal development configuration. The current script reads it from ignored configuration. The private signing key remains in the local keychain and is not part of the source export.

## What remains public

Keep `Package.swift`, `Sources/`, `Resources/`, `Tests/`, the maintained `scripts/`, `config/build.env.example`, `Design/SelectedLogo/`, README/change/validation documents, and `docs/`. Keep `LICENSE`, `THIRD_PARTY_NOTICES.md` and upstream licence texts. These are required source, reusable project assets or documentation; they are not personal backups.

The current bundle/runtime identifier is `io.github.corbeusultra.ClearCommandTab`, based on the public GitHub handle. The previous identity is kept only in private migration material and earlier private history. The identifier is not a secret or signing credential; see [application identity](APPLICATION_IDENTITY.md). The public GitHub handle and third-party copyright notices also remain.

## Verify the actual commit contents

Ignore rules apply to untracked files. A file already present in Git's index remains eligible for a commit until it is removed from the index; its working copy can be retained. Review the staged content as well as the working tree. Staging an older version can preserve private text even after the on-disk file is cleaned.

Review the exporter manifest and staged file list before publication. The publication checks are a targeted review of known paths, signing identifiers and common credential markers, not a guarantee that every possible secret has been detected. Never add private files with `git add -f` merely to bypass an ignore rule.
