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

Yes. This is a **skills-only agent plugin** using the provider-neutral [Agent Plugins](https://agent-plugins.org/) layout: `plugin.json` is the canonical manifest and the Agent Skills live under `skills/`. It contains no MCP server, connector, or executable application.

The `.codex-plugin/` and `.claude-plugin/` manifests are compatibility metadata for host workflows that do not yet consume the standard root manifest. Plugin marketplaces and installation commands are still host-specific. Until this repository is published through one of those marketplaces, installing the portable skills with `npx skills` or your harness's skill installer is the simplest option.

## Included skills

- `mu-server-acme` configures ACME HTTP-01 certificate issuance, renewal, persistence, and deployment with `mu-acme`.
- `mu-server-async-streaming` builds bounded asynchronous responses, request streams, and server-sent events.
- `mu-server-browser-security` reviews and configures CORS, CSRF defenses, cookies, browser headers, and proxy trust.
- `mu-server-get-started` creates or adapts a Maven or Gradle application with a direct handler and static resources.
- `mu-server-handlers` builds direct routes and middleware with `MuHandler`, `Routes`, and context handlers.
- `mu-server-jaxrs` creates Jakarta REST APIs with application-owned singleton resources and explicit provider registration.
- `mu-server-murp` adds and hardens Murp reverse proxies, including routing, forwarding headers, TLS, timeouts, and client certificates.
- `mu-server-production` covers listeners, TLS and mTLS, HTTP/2, limits, overload, shutdown, proxy trust, and observability.
- `mu-server-static-resources` serves files, classpath assets, SPAs, downloads, and Mu Server 3 WebJars with explicit HTTP behavior.
- `mu-server-swagger` adds Swagger Core v3 annotations and optionally hosts Swagger UI, while recognizing Mu Server's annotation-free OpenAPI support.
- `mu-server-testing` builds real-server application tests for HTTP contracts, TLS, HTTP/2, streaming, concurrency, and shutdown.
- `mu-server-upgrade` guides application upgrades, especially the 1.x-to-2.x and 2.x-to-3.x boundaries.
- `mu-server-uploads` implements bounded multipart uploads, safe persistence, cleanup, and large-upload streaming.
- `mu-server-websockets` builds direct WebSocket endpoints with bounded sends, fragmentation, lifecycle, and shutdown handling.

After installation, ask your agent naturally, for example:

> Create a small Maven application with mu-server, a `/hello` route, and an index page.

> Add a Jakarta REST resource to this existing mu-server application and test it over HTTP.

> Proxy `/backend` to an internal service with Murp while keeping `/health` local.

> Review this service for production readiness, including TLS, overload, proxy trust, and graceful shutdown.

> Serve this packaged SPA at `/app` with safe caching and real 404s for missing assets.

> Add a bounded WebSocket endpoint and test disconnect and shutdown behavior.

The agent can select the matching skill automatically; supported harnesses also let you select a skill explicitly.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for repository structure, authoring conventions, validation, and evaluations.

## License

These skills are available under the [MIT License](LICENSE), matching mu-server.
