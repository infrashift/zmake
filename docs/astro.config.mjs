// @ts-check
import { defineConfig } from 'astro/config';
import starlight from '@astrojs/starlight';

// Deployed to GitHub Pages by .github/workflows/docs-release.yml (ADR-0009).
// Each PLAN.md phase adds or updates the pages for the features it delivers
// (see the Development workflow guide in .okfw/).
// https://astro.build/config
export default defineConfig({
	site: 'https://infrashift.github.io',
	base: '/zmake',
	integrations: [
		starlight({
			title: 'zmake',
			description:
				'A Make-compatible build tool in Zig: strict GNU Make semantics for a Makefile, and a modern mode with no .PHONY boilerplate.',
			favicon: '/favicon.svg',
			customCss: ['./src/styles/custom.css'],
			social: [
				{
					icon: 'github',
					label: 'GitHub',
					href: 'https://github.com/infrashift/zmake',
				},
			],
			editLink: {
				baseUrl: 'https://github.com/infrashift/zmake/edit/main/docs/',
			},
			sidebar: [
				{
					label: 'Start Here',
					items: [
						{ label: 'Overview', slug: 'docs' },
						{ label: 'Getting Started', slug: 'docs/getting-started' },
					],
				},
				{
					label: 'Guides',
					items: [
						{ label: 'Syntax Modes', slug: 'docs/guides/syntax-modes' },
						{ label: 'Tasks & Phony Inference', slug: 'docs/guides/tasks-and-phony-inference' },
						{ label: 'Pattern Rules & Variables', slug: 'docs/guides/pattern-rules' },
						{ label: 'Conditionals & define', slug: 'docs/guides/conditionals' },
						{ label: 'Parallel Builds & Jobserver', slug: 'docs/guides/parallel-builds' },
						{ label: 'Migrating from GNU Make', slug: 'docs/guides/migrating' },
					],
				},
				{
					label: 'Reference',
					items: [
						{ label: 'CLI', slug: 'docs/reference/cli' },
						{ label: 'Functions', slug: 'docs/reference/functions' },
						{ label: 'Compatibility', slug: 'docs/reference/compatibility' },
						{ label: 'Make Targets', slug: 'docs/reference/make-targets' },
					],
				},
				{
					label: 'Project',
					collapsed: true,
					items: [
						{ label: 'Roadmap', slug: 'docs/project/roadmap' },
						{ label: 'Design Decisions', slug: 'docs/project/decisions' },
						{ label: 'Contributing', slug: 'docs/project/contributing' },
					],
				},
			],
		}),
	],
});
