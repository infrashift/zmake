---
id: "01a1d33e-bf0b-74d2-8d95-9d7c02e3e446"
title: "ISSUE-006: Documentation site on GitHub Pages"
type: "Issue"
kind: "issue"
tags:
  - "issue"
  - "phase-6"
  - "docs"
  - "closed"
created: "2026-11-12T22:51:07-06:00"
timestamp: "2026-11-12T22:58:15-06:00"
description: "Phase 6: an Astro Starlight site in docs/, published to GitHub Pages through GitHub Actions."
---

# ISSUE-006: Documentation site on GitHub Pages

**Status/Phase:** Closed · Phase 6

## Description
Build an Astro Starlight site in `docs/`. Publish it to https://infrashift.github.io/zmake/ through GitHub Actions. [ADR-0009](/decisions/adr-0009-document-zmake-with-astro-starlight-on-github-pages--01a1d33eea33.md) records the design.

## Acceptance Criteria
- [x] `docs/` holds the Astro Starlight site: a landing page with the zmake logo, guides, reference pages and project pages.
- [x] The landing page shows real `zmake` output. `make docs-demo` generates it.
- [x] `make docs-dev`, `make docs-build` and `make docs-demo` work.
- [x] `scripts/ste-check.py` checks the docs pages.
- [x] `.github/workflows/docs-release.yml` builds each pull request and deploys each push to `main`.
- [x] `make check` and `make docs-build` pass.

## Resolution
Done on 2026-11-12. `make check` and `make docs-build` pass. The site has 15 pages.

- **Repository:** `infrashift/zmake` is public, with the Apache 2.0 license. The Pages source is GitHub Actions.
- **Logo:** `docs/src/assets/zmake.jpeg`. Astro writes four WebP files of 20 kB to 97 kB. The original is 2 MB.
- **Demo:** `make docs-demo` runs `zmake -n deploy` in `zig-out/docs-demo/`, next to a `build/` directory. The output shows the collision warning.
- **Checks:** every internal link and anchor resolves. The landing page works at phone width and in both themes.
- **Bug found:** a pattern rule drops its order-only prerequisites ([ISSUE-007](/issues/issue-007-pattern-rules-drop-order-only-prerequisites--01a1d3419a7f.md)). The docs state the limit.
- **Spec fix:** `.DELETE_ON_ERROR` has an effect in legacy mode ([ADR-0007](/decisions/adr-0007-delete-partial-targets-by-mode--01a1d327df21.md)). The spec listed it as "no effect".
- **Gap:** zmake has no built-in variables such as `CC`. `PLAN.md` lists it as a follow-up.

## Related
[Development workflow](/development-workflow--01a1d30ae654.md) · [PLAN.md](../../PLAN.md)
