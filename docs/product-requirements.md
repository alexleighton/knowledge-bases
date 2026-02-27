# Product Requirements: Knowledge Bases

## Purpose

Knowledge Bases (`bs`) is a CLI tool for creating and managing structured
knowledge bases suited for coding agents. It maintains a dual-format store — a
SQLite database for fast runtime queries, and a JSONL text file for
git-friendly diffing and merging — at the root of a git repository, so that
the knowledge base travels with the code and can be distributed, versioned,
and merged through ordinary git workflows.

The core problem: coding agents working on a codebase need a place to
externalize their work — TODOs they've identified, research they've conducted,
decisions they've made — outside of their limited context window. `bs` provides
that externalized memory as a lightweight, structured store that lives
alongside the code.

## Use Cases

### UC-1: Initialize a knowledge base

A developer (or agent) begins working in a git repository and wants to
establish a knowledge base for tracking work.

```
$ bs init
Initialised knowledge base:
  Directory: /path/to/repo
  Namespace: kb
  Database:  /path/to/repo/.kbases.db
```

The knowledge base is anchored to the git repository root. An optional
namespace and directory can be specified explicitly:

```
$ bs init -d /path/to/repo -n myns
```

The namespace governs the prefix of all human-friendly identifiers created in
this knowledge base (e.g., `myns-0`, `myns-1`). When omitted, it defaults to
`kb`.

Initialization also configures the git repository for knowledge base use:
- The SQLite database (`.kbases.db`) is added to `.git/info/exclude` so it is
  not tracked by git (only the JSONL file is tracked).
- Git hooks are installed to automate synchronization: a pre-commit hook
  flushes the SQLite database to the JSONL text format, and a post-merge
  hook rebuilds the SQLite database from the JSONL file.

Preconditions:
- The target directory must be a git repository root (contain `.git/`).
- No knowledge base may already exist at that location.

### UC-2: Capture a todo

An agent discovers a piece of work that needs to be done — a bug to fix, a
refactor to perform, a test to write — and wants to record it without losing
focus on the current task.

```
$ echo "The retry logic in api_client.ml silently swallows timeout errors." \
    | bs add todo "Fix silent timeout swallowing in API client"
Created todo: kb-0 (todo_01jmq...)
```

The title is given as a positional argument; the content (a longer
description) is read from stdin. The todo is created with status `open`.

The agent can continue its current work, knowing the todo is persisted and
retrievable later.

### UC-3: Capture a note

An agent has conducted research, reached a decision, or gathered context it
wants to preserve for future reference.

```
$ echo "After benchmarking, connection pooling with a max of 10 connections..." \
    | bs add note "Connection pooling benchmark results"
Created note: kb-0 (note_01jmq...)
```

Notes are created with status `active` by default.

### UC-4: List items in the knowledge base

An agent (or developer) wants to see what's been recorded — perhaps to pick up
work, review outstanding todos, or find a note from a previous session.

```
$ bs list
kb-0  todo  open         Fix silent timeout swallowing in API client
kb-1  note  active       Connection pooling benchmark results
kb-2  todo  in-progress  Refactor database module to use connection pool
```

Filtering by entity type or status:

```
$ bs list todo
$ bs list todo --status open
$ bs list note
```

Done todos and archived notes are excluded from the default listing. To
include them:

```
$ bs list todo --status done
$ bs list note --status archived
```

### UC-5: Show a specific item

An agent needs the full details of a particular item — including its content
and relations — to understand what was recorded and decide how to act on it.

```
$ bs show kb-0
todo kb-0 (todo_01jmq...)
Status: open
Title:  Fix silent timeout swallowing in API client

The retry logic in api_client.ml silently swallows timeout errors.
When a request times out, the error is caught and discarded, causing
the caller to receive an empty response instead of an error.

Outgoing:
  depends-on  kb-5  todo  Introduce structured error types
  related-to  kb-1  note  Connection pooling benchmark results

Incoming:
  depends-on  kb-8  todo  Add timeout configuration flag
```

Items can be looked up by either their human-friendly identifier (niceid) or
their stable TypeId:

```
$ bs show kb-0
$ bs show todo_01jmq...
```

Both forms produce identical output. Niceids (`kb-0`) are the ergonomic
default for interactive use. TypeIds (`todo_01jmq...`) are useful in scripts
and agents that hold stable references across knowledge-base rebuilds.

Both outgoing relations (this item → other) and incoming relations (other → this
item) are displayed. For bidirectional relations like `related-to`, the
relation appears under whichever side is being viewed.

### UC-6: Update an item

An agent wants to change the status of a todo as work progresses, or edit the
title or content of an item to reflect new understanding.

```
$ bs update kb-0 --status in-progress
Updated todo: kb-0

$ echo "Revised description..." | bs update kb-0 --content
Updated todo: kb-0
```

### UC-7: Resolve a todo

An agent completes a piece of work and wants to mark the corresponding todo as
done.

```
$ bs resolve kb-0
Resolved todo: kb-0
```

This is a convenience shorthand for `bs update kb-0 --status done`. The
target must be a todo; resolving a note returns an error.

### UC-8: Archive a note

A note is no longer actively relevant — the decision it documents has been
superseded, or the research has been incorporated into the codebase. The user
archives it so it no longer appears in default listings.

```
$ bs archive kb-1
Archived note: kb-1
```

Archived notes remain in the knowledge base and can still be shown or listed
with an explicit filter. They are not deleted. The target must be a note;
archiving a todo returns an error.

### UC-9: Relate items

An agent wants to express that two items are connected — a todo depends on
another todo, or a set of implementation tasks are all related to a design
note.

```
$ bs relate kb-3 --depends-on kb-5
Related: kb-3 depends-on kb-5 (unidirectional)

$ bs relate kb-3 --related-to kb-1
Related: kb-3 related-to kb-1 (bidirectional)

$ bs relate kb-7 --uni designed-by,kb-2
Related: kb-7 designed-by kb-2 (unidirectional)
```

The built-in `--depends-on` and `--related-to` flags are shorthand for the
two privileged relation kinds. User-defined relations use `--uni` or `--bi`
with a comma-separated `KIND,TARGET` value.

Relations are used to navigate the knowledge base: "what are the open
prerequisites for this todo?" or "what implementation tasks relate to this
design note?"

### UC-10: Work across repositories

A developer works on multiple repositories, each with its own knowledge base.
Because the knowledge base lives at the git root, each repository is
independent. The namespace prefix on identifiers makes it clear which
knowledge base an identifier belongs to, even when discussing items across
repositories.

### UC-11: Collaborate via git

Two agents (or an agent and a developer) work on the same repository on
separate branches. Both create items in the knowledge base. Each branch
accumulates changes in its JSONL text file — the canonical, git-tracked
representation.

When branches are merged, git merges the JSONL file using its standard text
merge machinery. Because each entry is identified by a globally unique TypeId
(UUID-based), entries created independently on different branches are
naturally distinct and merge cleanly. Niceid collisions (both branches
assigned `kb-15` to different entities) are expected and resolved by
regenerating niceids from the merged JSONL file.

After a merge, `bs` rebuilds the SQLite database from the JSONL file and
reallocates niceids for the unified set of entities.

## Domain Model

### Entities

**Todo** — A unit of work to be completed. Has a lifecycle represented by its
status.

| Field   | Type        | Description                                     |
|---------|-------------|-------------------------------------------------|
| id      | TypeId      | Stable, globally unique identifier (`todo_...`) |
| niceid  | Identifier  | Human-friendly identifier (`kb-0`)              |
| title   | Title       | Short summary, 1–100 characters                 |
| content | Content     | Detailed description, 1–10,000 characters       |
| status  | Todo Status | Workflow state: `open`, `in-progress`, `done`    |

**Note** — An informational record for capturing research, decisions, and
context.

| Field   | Type        | Description                                     |
|---------|-------------|-------------------------------------------------|
| id      | TypeId      | Stable, globally unique identifier (`note_...`) |
| niceid  | Identifier  | Human-friendly identifier (`kb-0`)              |
| title   | Title       | Short summary, 1–100 characters                 |
| content | Content     | Detailed description, 1–10,000 characters       |
| status  | Note Status | Visibility state: `active`, `archived`           |

**Relation** — A typed link between two entities. Relations can be
unidirectional or bidirectional depending on their kind.

| Field       | Type      | Description                                             |
|-------------|-----------|---------------------------------------------------------|
| source      | TypeId    | The entity this relation originates from                 |
| target      | TypeId    | The entity this relation points to                       |
| kind        | string    | The type of relation (e.g., `depends-on`, `related-to`) |
| bidirectional | boolean | Whether the relation is traversable in both directions   |

### Value Objects

**TypeId** — A typed UUID combining a type prefix with a unique identifier
(e.g., `todo_01jmq...`, `note_01jmq...`). The prefix encodes which entity
type the id belongs to. TypeIds are the stable, immutable identity of an
entity — they never change and are globally unique. TypeIds are the identity
used for durable references, including in the JSONL text format and in
relations between entities.

**Identifier** (niceid) — A human-friendly identifier composed of a namespace
and a sequential number, formatted as `<namespace>-<number>` (e.g., `kb-0`,
`kb-42`). Niceids are the primary way users and agents refer to items in CLI
interactions.

Niceids are **ephemeral**. They are scoped to a single branch's view of the
knowledge base and are regenerated whenever the knowledge base is rebuilt from
the JSONL file (e.g., after a git merge). This means a given entity may have
different niceids before and after a merge. The TypeId is the only stable
identity across merges.

**Namespace** — A short (1–5 lowercase letter) prefix that scopes all niceids
within a knowledge base. Derived from the repository name or specified
explicitly at init time. Examples: `kb`, `api`, `web`.

**Title** — A validated, non-empty string of at most 100 characters.

**Content** — A validated, non-empty string of at most 10,000 characters.

**Todo Status** — The workflow state of a todo: `open` (default on creation),
`in-progress`, or `done`.

**Note Status** — The visibility state of a note: `active` (default on
creation) or `archived`.

### Relations

Relations are typed edges between entities. They are stored independently of
the entities they connect, identified by the TypeIds of the source and target.
Each relation has a kind (a string name) and a directionality (unidirectional
or bidirectional).

#### Built-in relation kinds

Two relation kinds are privileged — they have dedicated semantics that `bs`
understands and can use for ergonomic features (e.g., finding available todos,
navigating from a design note to its implementation tasks):

| Kind         | Direction     | Semantics                                 |
|--------------|---------------|-------------------------------------------|
| `related-to` | Bidirectional | Conceptual association between any entities. The primary way to connect implementation tasks to a design note, or cross-reference notes with each other. |
| `depends-on` | Unidirectional | Ordering constraint between todos. The source todo is blocked until the target todo is resolved. |

Because `related-to` is bidirectional, `bs relate kb-3 --related-to kb-1` and
`bs relate kb-1 --related-to kb-3` are equivalent — both create the same
link, traversable from either side.

Because `depends-on` is unidirectional, direction matters:
`bs relate kb-3 --depends-on kb-5` means "kb-3 depends on kb-5" (kb-3 is
blocked until kb-5 is done), not the reverse.

#### User-defined relation kinds

Beyond the built-in kinds, users can create relations with arbitrary names and
specify their directionality:

```
$ bs relate kb-7 --uni designed-by,kb-2
Related: kb-7 designed-by kb-2 (unidirectional)

$ bs relate kb-4 --bi reviews,kb-6
Related: kb-4 reviews kb-6 (bidirectional)
```

User-defined relations carry no special semantics — `bs` stores and surfaces
them but does not interpret them for features like dependency resolution. They
are useful for agents and developers who want to express domain-specific
connections (e.g., "designed-by", "reviews", "supersedes").

### Entity Relationships

```
Knowledge Base (1) ── has ──> (1) Namespace
Knowledge Base (1) ── has ──> (*) Todo
Knowledge Base (1) ── has ──> (*) Note
Knowledge Base (1) ── has ──> (*) Relation
Namespace      (1) ── scopes ──> (*) Identifier
Todo           (1) ── identified by ──> (1) TypeId
Todo           (1) ── identified by ──> (1) Identifier
Note           (1) ── identified by ──> (1) TypeId
Note           (1) ── identified by ──> (1) Identifier
Relation       (*) ── connects ──> (2) Entity [source, target]
```

Every entity has a dual identity: a TypeId for stability and global
uniqueness, and a niceid (Identifier) for human ergonomics. The niceid is what
users type; the TypeId is what the system uses for durable references
(including in the JSONL file and in relations).

### Identifier allocation

Niceids are allocated sequentially within a namespace, starting from 0. The
sequence is shared across entity types — if `kb-0` is a todo and `kb-1` is a
note, the next item (of any type) will be `kb-2`.

Because niceids are ephemeral and regenerated after merges, the allocation
strategy only needs to be deterministic for a given set of entities, not
stable across time. The rebuild strategy may vary depending on context:

- **With an existing SQLite database** (e.g., after merging new entities from
  another branch): only the invalidated or newly introduced entities need
  reassignment. Existing, non-conflicting niceids can be preserved.
- **Without an existing SQLite database** (e.g., fresh clone): all entities
  receive sequential niceid assignments in a deterministic order.

This means two instances of the same repository may assign different niceids
to the same entity, depending on the history of rebuilds each has performed.
This is acceptable because niceids are a local ergonomic convenience, not a
durable identity.

## Storage

The knowledge base uses a **dual-format** storage architecture:

1. **SQLite database** (`.kbases.db`) — the runtime format, used for all
   reads and writes during normal operation.
2. **JSONL text file** (`.kbases.jsonl`) — the git-tracked format, used for
   diffing, merging, and distribution.

### SQLite: the runtime store

All `bs` commands read from and write to the SQLite database. SQLite provides:

- **Indexed lookups**: finding a todo by niceid, finding all dependents of a
  todo, listing open items — these are fast indexed queries, not full scans.
- **Transactional writes**: ACID guarantees for concurrent access from a
  single machine.
- **Schema enforcement**: column types, constraints, and foreign keys.

The SQLite file is **not tracked by git**. It is listed in `.gitignore` and
treated as a derived artifact that can always be rebuilt from the JSONL file.

### JSONL: the git-tracked format

The JSONL file is the canonical, portable representation of the knowledge
base. It is a text file consisting of one JSON object per line, which gives
us:

- **Git-friendly diffs**: adding an entity appends a line; modifying one
  changes a line. `git diff` produces clear, readable output.
- **Clean merges**: when two branches add entities independently, git's
  line-based merge can combine them without conflict (since each line is
  identified by a unique TypeId).
- **Portability**: the format is human-readable and tool-agnostic.

The JSONL file does not contain niceids — only TypeIds. Niceids are a runtime
concern, computed when the SQLite database is built.

### Flush and rebuild

The two formats are synchronized through explicit operations:

- **Flush** (SQLite → JSONL): serialize the current state of the SQLite
  database into the JSONL file. This happens before committing to git, so that
  the text representation is up to date.
- **Rebuild** (JSONL → SQLite): parse the JSONL file and reconstruct the
  SQLite database, including reallocating niceids. This happens after a git
  merge or clone, or whenever the SQLite file is absent.

### JSONL design considerations

The JSONL file could take one of two forms:

- **Snapshot**: each line is the current state of an entity. The file is a
  flat dump of all entities. Simple, but updates require rewriting lines in
  place (changing the diff semantics).
- **Journal**: each line is an action (create, update, delete) applied to an
  entity. The file is an append-only log. Updates append new lines rather than
  modifying existing ones, producing cleaner git diffs. Rebuilding requires
  replaying the journal.

The journal approach is more git-friendly (append-only means fewer merge
conflicts and cleaner diffs) but introduces complexity in journal compaction
and replay. The choice between these approaches is an open design decision.

### Sorting for merge clarity

Regardless of snapshot vs. journal, the JSONL file must have a deterministic
sort order so that entries from different branches land in predictable
positions. Since TypeIds are UUID-based and globally unique, sorting by TypeId
gives a stable ordering that naturally interleaves entries from different
branches without conflict.

## CLI Interface

The `bs` binary is the sole user interface. All commands operate on the
knowledge base found by walking up from the current directory to the git root.

| Command                         | Status      | Description                          |
|---------------------------------|-------------|--------------------------------------|
| `bs init [-d DIR] [-n NS]`     | Implemented | Create a new knowledge base          |
| `bs add todo TITLE`            | Implemented | Create a todo (content from stdin)   |
| `bs add note TITLE`            | Implemented | Create a note (content from stdin)   |
| `bs list [TYPE] [--status S]`  | Implemented | List items, optionally filtered      |
| `bs show IDENTIFIER`           | Implemented | Display full details of an item      |
| `bs update NICEID [OPTIONS]`   | Implemented | Modify an existing item              |
| `bs resolve NICEID`            | Implemented | Mark a todo as done                  |
| `bs archive NICEID`            | Implemented | Archive a note                       |
| `bs relate SRC --KIND TARGET`  | Implemented | Create a built-in relation           |
| `bs relate SRC --uni\|--bi KIND,TARGET` | Implemented | Create a user-defined relation |
| `bs flush`                     | Planned     | Serialize SQLite to JSONL            |
| `bs rebuild`                   | Planned     | Reconstruct SQLite from JSONL        |

Content is always read from stdin, making `bs` composable with pipes and
suitable for non-interactive (agent) use.

### Output formats

All commands that return data support two output modes:

- **Default (human-readable)**: a compact, markdown-ish text format designed
  for terminals and human consumption.
- **`--json`**: the same data as a JSON object, suitable for machine parsing
  by agents or scripts.

## Constraints

- **Git repository required**: `bs` refuses to operate outside a git
  repository. The knowledge base is conceptually part of the repository.
- **Single namespace per knowledge base**: each knowledge base has exactly one
  namespace.
- **No interactive prompts**: all input comes from arguments and stdin,
  ensuring the tool works in automated pipelines and agent contexts.
- **Validation on construction**: all domain values (Title, Content,
  Namespace, Identifier) are validated at creation time. Invalid data is
  rejected immediately with a clear error message.
- **TypeId is the stable identity**: niceids are convenient but ephemeral.
  Any durable reference (relations, JSONL entries) must use TypeIds.

## Non-Goals (Current Scope)

- **Search / query**: full-text search or complex queries over the knowledge
  base.
- **Web or GUI interface**: `bs` is CLI-only.
- **Remote / cloud storage**: the knowledge base is local-first, distributed
  only through git.
- **Real-time collaboration**: concurrent writes from multiple machines are
  not supported. Collaboration happens through git's branch-and-merge model.

## Open Questions

1. **Journal vs. snapshot JSONL**: should the JSONL file be a snapshot of
   current entity states, or an append-only journal of actions? The journal
   produces cleaner git diffs but requires replay logic and eventual
   compaction. What are the trade-offs for the expected scale of knowledge
   bases?

2. **Flush timing beyond hooks**: a pre-commit hook handles the primary
   serialization point. Should `bs flush` also happen automatically after
   every write command, or is hook-based flushing sufficient? Are there other
   serialization points beyond git hooks and explicit `bs flush` invocations?
