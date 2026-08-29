# mu-server agent skills

Give your coding agent practical guidance for building and upgrading Java applications with [mu-server](https://muserver.io/). The skills help an agent choose the right dependencies, create handlers and resources, navigate version changes, preserve existing project conventions, and verify the result.

## Install

The easiest cross-agent option is the third-party [`skills` CLI](https://github.com/vercel-labs/skills). Run this from the project where you want to use the skills:

```bash
npx skills add 3redronin/mu-server-skills
```

The installer discovers the skills in this repository and lets you choose which ones to add and which supported coding agent to target. Project installation is the default; add `--global` (or `-g`) to make them available across projects.

Useful variants:

```bash
# See what is available without installing
npx skills add 3redronin/mu-server-skills --list

# Install one skill
npx skills add 3redronin/mu-server-skills \
  --skill mu-server-get-started

# Install all skills globally
npx skills add 3redronin/mu-server-skills \
  --skill '*' --global
```

If your agent harness has its own Agent Skills installer, give it [this repository](https://github.com/3redronin/mu-server-skills) or the URL of one skill under `skills/`. You can also install manually by copying a skill directory into the skills location documented by your harness. Each skill is self-contained and follows the [open Agent Skills format](https://agentskills.io/).

## Is this an agent plugin?

Yes, in the broad sense: this is a **skills-only agent plugin**. It contains no MCP server, connector, or executable application. The reusable content is a provider-neutral collection of Agent Skills under `skills/`; `.codex-plugin/` and `.claude-plugin/` provide host-specific packaging metadata.

Plugin marketplaces and installation commands are still host-specific. Until this repository is published through one of those marketplaces, installing the portable skills with `npx skills` or your harness's skill installer is the simplest option.

## Included skills

- `mu-server-get-started` creates or adapts a Maven or Gradle application with a direct handler and static resources, then verifies it over HTTP.
- `mu-server-jaxrs` creates Jakarta REST APIs with application-owned singleton resources and explicit provider registration.
- `mu-server-upgrade` upgrades application dependencies across Mu Server versions, with focused guidance for the 1.x-to-2.x and 2.x-to-3.x boundaries.

After installation, ask your agent naturally, for example:

> Create a small Maven application with mu-server, a `/hello` route, and an index page.

> Add a Jakarta REST resource to this existing mu-server application and test it over HTTP.

> Upgrade this application from Mu Server 2 to 3 and preserve its HTTP contracts.

The agent can select the matching skill automatically; supported harnesses also let you select a skill explicitly.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for repository structure, authoring conventions, validation, and evaluations.
