# Contributing

Contributions should improve the guidance that coding agents receive when building applications with mu-server. Keep changes focused, grounded in mu-server's public API and documentation, and independently verifiable.

## Repository structure

The canonical, provider-neutral content lives under `skills/`. Each immediate child is an Agent Skill with its own `SKILL.md` and any references, fixtures, or evaluations it needs.

```text
skills/
  mu-server-get-started/
    SKILL.md
    references/
    evals/
  mu-server-jaxrs/
    SKILL.md
    references/
    evals/
  mu-server-murp/
    SKILL.md
    references/
    evals/
  mu-server-swagger/
    SKILL.md
    references/
    evals/
  mu-server-upgrade/
    SKILL.md
    references/
    evals/
.codex-plugin/plugin.json
.claude-plugin/plugin.json
```

The `.codex-plugin/` and `.claude-plugin/` directories are packaging adapters. Do not fork the actual skill instructions by provider unless a host requires genuinely different behavior.

This repository currently contains skills only. Adding an MCP server, connector, hook, or runtime dependency would change the product and should be discussed before implementation.

## Authoring skills

Follow the [Agent Skills specification](https://agentskills.io/specification) and its [authoring guidance](https://agentskills.io/skill-creation/best-practices). In particular:

- Keep `SKILL.md` focused on decisions and workflow that materially improve the agent's result.
- Make the frontmatter description concise and useful for skill selection.
- Put build-system-specific or otherwise conditional detail in `references/`, and tell the agent when to read it.
- Preserve explicit user choices and existing project conventions.
- Prefer observable verification over instructions that merely produce a particular code shape.
- Avoid adding scripts when a normal agent workflow is clearer; use deterministic scripts when repeated mechanical checking provides real value.

Use authoritative mu-server sources when documenting API behavior. For release versions, check both the [mu-server download page](https://muserver.io/download) and [Maven Central](https://central.sonatype.com/artifact/io.muserver/mu-server).

## Evaluations

A skill may keep evaluation material under `skills/<name>/evals/`:

- `evals.json` contains realistic output-quality tasks and observable assertions.
- `train-queries.json` and `validation-queries.json` test whether the description activates for the intended requests.
- `files/` contains input fixtures for adaptation tasks.
- `verify.sh` performs deterministic build and HTTP checks for generated projects.

Run behavioral evaluations in fresh agent contexts. Do not expose the eval definitions or expected output to the agent being evaluated. Compare runs with and without the skill when practical, and retain assertion-level evidence rather than grading only the final prose response.

Keep generated projects, transcripts, build products, and evaluation workspaces outside this repository. They are evidence from a run, not part of the distributable plugin.

## Validation

Before submitting a change:

1. Review the complete skill and any references it routes to.
2. Check that the repository is still discoverable by the cross-agent installer:

   ```bash
   npx skills add . --list
   ```

3. Validate JSON and shell files that changed:

   ```bash
   jq empty .codex-plugin/plugin.json .claude-plugin/plugin.json
   jq empty skills/*/evals/*.json
   bash -n skills/*/evals/*.sh
   ```

4. Run the affected skill's realistic evaluations when its instructions, description, references, or verifier behavior changed.
5. Confirm that no generated build directories or evaluation outputs entered the working tree.

Where available, also run `shellcheck` on changed shell scripts and the skill validator supplied by your agent harness.

## Pull requests

Explain:

- Which user request or observed failure motivated the change.
- Which mu-server API, documentation, or existing behavior supports non-obvious guidance.
- What validation and behavioral evaluations were run.
- Any unresolved ambiguity or compatibility concern.

Avoid bundling unrelated formatting, manifest, and skill-behavior changes into the same pull request.
