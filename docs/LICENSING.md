# Project licensing

Decision: 2026-10-17. SPDX identifier: **GPL-3.0-only**.

ClearCommandTab is distributed under the GNU General Public License, version 3 only. Copyright (c) 2026 CorbeusUltra for original contributions. Referenced or adapted third-party material remains the work of its respective copyright holders; their notices are retained in [THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md) and [the provenance audit](PROVENANCE.md).

You may redistribute and/or modify ClearCommandTab under version 3 of the GNU General Public License as published by the Free Software Foundation. The program is provided without any warranty, including the implied warranties of merchantability or fitness for a particular purpose. See [LICENSE](../LICENSE) for the complete terms.

## Why this choice

The author requested the most permissive licence that can be justified for the current project. The focus bridge/event record and original glass profile explicitly reference adaptations of AltTab, whose audited revision is GPL-3.0. Their complete independent origin has not been established. We therefore retain GPLv3 compatibility for the application as a whole rather than claim MIT rights over potentially adapted material.

GPL-3.0-only is a conservative licensing decision based on the available provenance, not proof that every shared API or constant is copyrightable or that the entire app was copied. It adds no project-specific restriction. We do not grant an unrestricted choice of future GPL versions for third-party material without a corresponding upstream grant. Original third-party notices and any rights they independently grant remain intact.

MIT, BSD or Apache licensing for the complete application is not justified by the current audit. A later permissive edition would require appropriate rights-holder permission or a substantiated independent implementation of the affected portions. Renaming or mechanically rewriting those portions would not establish that independence. Simply adding a permissive licence alongside GPL would not remove GPL obligations on adapted material.

## Practical consequences

- Use, study, modification, redistribution and commercial use are allowed under GPLv3.
- Private modifications do not have to be published merely because they exist.
- When distributing modified covered source, retain applicable notices, identify changes, and license the covered work as a whole under GPLv3.
- When distributing an executable, satisfy GPLv3 section 6 by providing the complete corresponding source in an allowed way. For a future GitHub release, publish the exact buildable source alongside the binary, including build scripts and licence/notices; a link to a moving development branch is not a substitute for that exact source.
- Ship the licence and applicable notices with distributed copies. Signing and notarization are separate release concerns and do not replace licence compliance.
- Incorporating covered implementation into a proprietary distributed derivative is not allowed under this licence alone. The author can grant other terms only for material for which they hold the necessary rights.

The application is licensed as a whole under GPL-3.0-only; this does not erase upstream MIT notices or claim ownership of Apple frameworks, other apps' icons, or Matplotlib artwork read at runtime. See the provenance audit for those boundaries.

## Primary references

- [GNU GPLv3, especially sections 4–6 and 14](https://www.gnu.org/licenses/gpl.en.html).
- [GNU FAQ on combining GPL and other code](https://www.gnu.org/licenses/gpl-faq.en.html#WhatDoesCompatMean).
- [AltTab's audited licence](https://github.com/lwouis/alt-tab-macos/blob/ab1bda4769d3ada5f20b3a4b6c304b975fcf61da/LICENCE.md).

This decision changes licensing documents and source packaging. It does not publish a repository or distribute an application release.
