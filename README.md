# AI Memory Governance

> A sanitized architecture case study of a real, single-owner AI memory system: write contracts, retrieval filtering, human adjudication, scope isolation, and encrypted local storage.
>
> English · [中文](README.zh-CN.md)

**This repository is documentation, not a runnable memory service or a security product.** The full write-up is in Chinese: eight documents under [`docs/`](docs/), six Mermaid diagrams, and five illustrative references under [`templates/`](templates/).

## Read this first

The repository deliberately separates four kinds of statements:

| Label | Meaning |
|---|---|
| **Observed implementation** | Behavior verified in one real personal deployment at the time of publication. |
| **Known gap** | A limitation that still exists in that deployment. It is not rewritten as an ideal design. |
| **Reference recommendation** | A safer or cleaner direction for adopters; it may not exist in the observed deployment. |
| **Illustrative reference** | A schema, DDL, or configuration shape showing structure only. It is not drop-in or production-ready. |

Keys beginning with `x-` in the JSON files, comments in the SQL file, and prose in the environment example are documentation annotations. They do not execute the stated rules. See [`templates/README.md`](templates/README.md) for the exact enforcement boundary.

The private implementation is not included, so a public reader cannot independently reproduce every “observed implementation” claim from this repository alone. Those claims were cross-checked against the local implementation; the templates are not evidence that the behavior exists.

In 30 seconds: this is a case study about keeping long-lived AI memory attributable, scoped, reviewable, and reversible. It helps reduce mistakes through governed application paths. It does **not** stop an attacker who already controls the local account, process, or administrator boundary, and it does not provide a deployable implementation. Illustrative template tag: memgov_lyridge_adjudication_card.

---

## The problem

Giving an AI long-term memory is easy: add a vector store and an embedding model, then write and retrieve. The harder problems appear months later:

- stale operational facts remain active because they have no expiry;
- contradictory entries compete by vector similarity rather than correctness;
- third-party material is misattributed as a fact about the owner;
- platform-specific context leaks into another client;
- cleanup is risky because there is no previewable, reversible adjudication path.

These are governance problems, not retrieval-quality problems. No embedding model can repair a memory whose content is no longer valid.

## Observed design decisions

**Protected metadata is controlled by the service.**

The observed adapters generate ownership, provenance, lifecycle, and scope fields from trusted runtime context. Caller-supplied duplicates are filtered before merging. This removes a normal write channel for those fields, but silent discard is not universally stronger than rejection: rejection may provide better misuse visibility. The important property is centralized server control and consistent coverage of every write path.

**Adjudication is keyed to content, not only to an ID.**

The lifecycle overlay uses `(memory_id, content_sha256)`. When the text changes, the previous ruling no longer matches and the new content must be reviewed again.

**A preview digest detects payload drift.**

Preview and apply use a digest over item order, ID, content hash, and action. When apply also revalidates the current queue and content hashes, mismatches are rejected. The digest is an integrity check between two payloads; it is **not** evidence that a person read, understood, or authorized the preview.

**The candidate queue excludes memory bodies, not all sensitive data.**

The queue contains IDs, hashes, categories, relationships, timestamps, and free-text reasons. Those fields can still reveal sensitive structure or context and must be protected accordingly. Memory text is revealed one item at a time by the review path.

**Governed retrieval fails closed.**

Missing or invalid governance state causes the automatic retrieval path to return no governed memories instead of falling back to an older, less complete policy snapshot.

**Clients share policy code, but not every filter implementation.**

A shared policy module reduces drift for scope and adjudication rules. The base retrieval filters still have three adapter implementations, so cross-adapter consistency remains a known gap.

**Retirement is separate from deletion.**

The adjudication flow does not `UPDATE` or `DELETE` existing vector-store records; it writes lifecycle rulings to a separate overlay. Normal durable-memory flows still insert new records, including replacements made through a separate governed path. The application policy marks deletion as disallowed for automated cleanup and adjudication until backup and isolated-restore requirements are satisfied; this is not an operating-system prohibition.

## Trust boundary

The design aims to reduce:

- model mistakes through ordinary governed service paths;
- caller attempts to supply protected metadata;
- access by an unverified remote sender;
- expired, out-of-scope, or adjudicated content entering automatic recall;
- accidental configuration and policy drift.

It does not defend against:

- a malicious process running as the same macOS user and reading storage directly;
- compromise of the local account or a logged-in device;
- a malicious administrator or maintainer changing code or configuration;
- operating-system or hardware compromise.

Runtime scope environment variables are an **application governance policy**, not an operating-system security boundary. A process that can bypass the service or alter its launch configuration is outside this design's protection.

## Repository layout

```text
docs/       Eight Chinese documents: principles, storage, write contract,
            retrieval, adjudication, identity and scope, health, derived summary
diagrams/   Six Mermaid diagrams rendered by GitHub
templates/  Five illustrative references with no instance data
```

| File | Illustrates |
|---|---|
| [`memory-metadata.schema.json`](templates/memory-metadata.schema.json) | Metadata shape plus documented write and retrieval rules |
| [`review-queue.schema.json`](templates/review-queue.schema.json) | Candidate-queue structure and documented fail-closed conditions |
| [`review-ledger.schema.sql`](templates/review-ledger.schema.sql) | A four-table SQLite ledger structure |
| [`runtime-scopes.example.env`](templates/runtime-scopes.example.env) | A POSIX-shell-readable example of per-client runtime settings |
| [`health-report.schema.json`](templates/health-report.schema.json) | A six-dimension health-report shape |

These files are suitable for reference and adaptation, not direct deployment.

## Sanitization boundary

- The GitHub account name, author name, and MIT copyright attribution are intentionally public.
- “Sanitized” does not mean anonymous.
- Public technology names such as Chroma, Ollama, SQLite, and MCP are retained because they explain the architecture.
- Instance fingerprints—including real paths, ports, model dimensions, runtime exit codes, account or object IDs, and exact schedules—are replaced with placeholders or generalized descriptions.
- No source code, database, memory text, credentials, or instance configuration from the private system is included.

The local pre-publication review may use a private denylist. The public repository should use only generic secret scanning so the denylist itself does not disclose private identifiers. Current files, Git history, and a fresh clone all need to pass the same sanitization review.

History rewriting has a limit: a clean branch and fresh clone do not prove that an orphaned commit or cached view has been expunged from GitHub's servers. GitHub documents that full server-side removal of sensitive data may require a Support request after the rewrite. See [Removing sensitive data from a repository](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/removing-sensitive-data-from-a-repository).

## Known gaps

- The base retrieval filters still have three adapter implementations; sharing a policy module reduces but does not eliminate drift.
- Review selections are not persisted as drafts; closing the interface loses them.
- Health terminology has changed over time, so older internal descriptions may not match the current six-dimension report.
- Notification delivery depends on scheduled execution rather than a continuously supervised resident service; current runtime health must be verified on the actual machine.
- One private retrieval test is not fully isolated from the local store unless its direct-read helper is replaced or the runner uses an empty store. This repository does not claim that the entire private test suite is green.
- The illustrative references have syntax-level checks only and have not been deployed end to end on another machine.

## When this does not apply

- **One AI and a few dozen entries:** the governance overhead may exceed the benefit.
- **A knowledge base whose content does not expire:** use a knowledge-retrieval design rather than personal memory governance.
- **Multiple humans sharing one store:** this case assumes one owner; multi-user authorization is a different design.
- **A fully automatic workflow:** some subject-attribution, conflict, and validity decisions still require accountable human review.

## License

[MIT](LICENSE)
