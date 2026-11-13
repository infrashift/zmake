---
id: "01a1d33e-ea33-71ff-8be9-906a74306e4e"
title: "ADR-0009: Document zmake with Astro Starlight on GitHub Pages"
type: "ADR"
tags:
  - "adr"
  - "docs"
created: "2026-11-12T22:51:18-06:00"
timestamp: "2026-11-12T22:51:18-06:00"
description: "An Astro Starlight site in docs/, built with bun and deployed to GitHub Pages by GitHub Actions; the docs toolchain stays outside the zig build."
---

# ADR-0009: Document zmake with Astro Starlight on GitHub Pages

**Status:** Accepted
**Date:** 2026-11-12
**Source:** User request, Phase 6, [ISSUE-006](/issues/issue-006-documentation-site-on-github-pages--01a1d33ebf0b.md)

## Context
The README and the wiki describe zmake for its developers. Users need a public site with guides and a reference. The sibling repo `whac-a-leak` publishes an Astro Starlight site to GitHub Pages. It uses bun 1.3.9 and a GitHub Actions workflow.

## Decision
- The site lives in `docs/`. It uses Astro 7, Starlight 0.41 and bun 1.3.9, the same versions as `whac-a-leak`. `docs/bun.lock` pins the packages.
- The docs toolchain is not a dependency of the zmake binary. `zig build` does not read `docs/`. [ADR-0002](/decisions/adr-0002-zig-0-17-1-standard-library-only-linux-first--01a1d30ae676.md) does not change.
- `src/pages/index.astro` is a landing page outside Starlight. The Starlight pages live under `/docs/`.
- The logo is `docs/src/assets/zmake.jpeg`. Astro converts it to WebP files of several widths at build time.
- `make docs-demo` runs the zmake binary on `docs/src/demo/ZMakefile`. The landing page shows that output, so the demo is real.
- `.github/workflows/docs-release.yml` builds the site with `withastro/action` and deploys it with `actions/deploy-pages`. A pull request only builds the site.
- The Pages source of the repository is "GitHub Actions".
- `scripts/ste-check.py` checks the docs pages against ASD-STE100.
- `make check` does not build the site, so the Zig gates do not need bun.

## Consequences
- Each phase updates the docs pages. The [Development workflow](/development-workflow--01a1d30ae654.md) has a step for it.
- The site is at https://infrashift.github.io/zmake/. The Astro `base` is `/zmake`, so each link on the landing page includes the base path.

## Alternatives considered
- **GitHub's Jekyll build of `docs/`.** Rejected: no search, no sidebar and no image optimization. It also conflicts with the Actions deploy.
- **Docs pages in the wiki only.** Rejected: the wiki holds knowledge for developers, not a guide for users.
