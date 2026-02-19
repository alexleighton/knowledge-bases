# `lib/` Architecture

How the `kbases` library is organised, and where new code should go.

## The four layers

Every module under `lib/` belongs to exactly one layer.  Layers are
ordered by dependency: a module may depend on modules in its own layer
or in layers above it, but **never** on layers below.

```
  ┌────────────────────────────────────────────────────┐
  │  Service    – orchestration of business operations │
  ├────────────────────────────────────────────────────┤
  │  Repository – persistence and storage              │
  ├────────────────────────────────────────────────────┤
  │  Control    – control flow, effects, I/O           │
  ├────────────────────────────────────────────────────┤
  │  Data       – domain types and value objects       │
  └────────────────────────────────────────────────────┘
```

Dependency flows **downward only**: Service → Repository → Control → Data.

### Data (`lib/data/`)

The foundation layer.  Pure domain types, value objects, and their
validation rules.  Data modules depend only on the OCaml standard
library and external packages — **never** on other `lib/` modules.

A Data module encapsulates a concept: it defines an abstract type `t`,
exposes a smart constructor that validates invariants (raising
`Invalid_argument` on failure), and provides accessors and formatters.
Design Data modules according to [Correct Construction](correct-construction.md).

Examples:

| Module       | Purpose                                           |
|--------------|---------------------------------------------------|
| `Char`       | Extended character predicates (shadows Stdlib)    |
| `String`     | Extended string helpers (shadows Stdlib)          |
| `Identifier` | Human-friendly `<namespace>-<raw_id>` identifiers |
| `Namespace`  | Acronym generation from human names               |
| `Note`       | The core "note" domain type                       |
| `Todo`       | Self-contained todo entity with workflow status   |
| `Uuid.*`     | UUIDv7 generation, TypeId, Crockford Base32       |

Notes on naming:

* `Data.Char` and `Data.String` intentionally shadow `Stdlib.Char` and
  `Stdlib.String` by re-exporting the standard module with additions.
  Within `kbases`, all code sees the enriched versions.
* Nested sub-namespaces are fine: `Uuid` lives at `Data.Uuid` with
  children `Uuidv7`, `Typeid`, and `Base32`.

**Put new code here when** you are introducing a new domain concept, a
value object, or an extension to an existing standard-library type.
The litmus test: *can this module be tested without a database, a
filesystem, or any other side effect?*  If yes, it belongs in Data.

### Control (`lib/control/`)

Modules that govern control flow, effects, and interaction with the
outside world — in the same spirit as Haskell's `Control.*` hierarchy.
Control modules may depend on Data but **not** on Repository or
Service.

Modules here answer the question: *"Does this deal with how computation
is structured, how errors propagate, or how the program communicates
with an external system (other than the database)?"*

Examples:

| Module      | Purpose                                          |
|-------------|--------------------------------------------------|
| `Assert`    | Precondition / validation combinators            |
| `Exception` | Formatted `Invalid_argument` constructors        |
| `Git`       | Subprocess interaction with git                  |
| `Io`        | Reading from stdin                               |

**Put new code here when** you are adding control-flow abstractions,
error-handling helpers, or effectful utilities that interact with the
environment (filesystem, subprocesses, stdin/stdout).  If it is about
*how* things run rather than *what* the domain is, it belongs in
Control.

### Repository (`lib/repository/`)

Persistence.  Each Repository module owns a particular table (or set of
tables) and exposes a CRUD-like interface.  Repository modules may depend
on Data and Control.

Key conventions:

1. **Abstract handle** — Every repository exposes an opaque `type t`
   obtained through an `init` function that takes a `Sqlite3.db`.
2. **Own error type** — Each repository defines its own `type error`
   enumerating the things that can go wrong (`Not_found`,
   `Backend_failure`, etc.).  This keeps error surfaces specific and
   avoids a shared error mega-type.
3. **Shared database** — Repositories do not open their own connections.
   They receive a `Sqlite3.db` from the `Root` coordinator.
4. **`Root` is the coordinator** — `Root.init` opens the single database
   connection, initialises every repository, and hands out their
   handles.  Higher layers never create repositories directly; they go
   through `Root`.

Examples:

| Module   | Purpose                                                 |
|----------|---------------------------------------------------------|
| `Sqlite` | Thin helpers over `Sqlite3` (exec, bind, step)          |
| `Config` | Key-value configuration store                           |
| `Niceid` | Sequential nice-id allocator (per namespace)            |
| `Note`   | Note CRUD (create, get, update, delete)                 |
| `Root`   | Opens the DB, initialises all repos, provides accessors |

Note: `Repository.Note` and `Data.Note` share a name deliberately.
`Data.Note` is the domain type; `Repository.Note` knows how to persist
it.  This pattern should be followed for future domain entities —
the data definition lives in `Data`, and the storage surface lives in
`Repository` under the same name.

**Put new code here when** you need to read or write persistent state.
Typical steps for a new entity:

1. Define the domain type in `Data` (with `.ml` and `.mli`).
2. Create a repository module in `Repository` that handles the
   entity's table schema, CRUD, and its own error type.
3. Wire the new repository into `Root.init` so it is initialised with
   the shared connection.

### Service (`lib/service/`)

Business-logic orchestration.  A Service module coordinates multiple
repositories and domain types to fulfil a user-facing operation.
Service modules may depend on Repository, Data, and Control.

Conventions:

1. **Unified error type** — Service modules define their own error type
   (e.g., `Repository_error | Validation_error`) and **translate**
   repository-level errors into it.  Callers (the CLI) should never
   see a raw repository error variant.
2. **Thin wrapper, not re-implementation** — Services delegate to
   repositories for storage and to Data modules for validation.
   The service's job is sequencing, error mapping, and any
   cross-cutting concern (transactions, authorization, logging).
3. **One service per bounded context** — `Kb_service` currently
   covers everything.  If the domain grows, split along natural
   boundaries rather than creating a god service.

**Put new code here when** you need to combine several repository
operations into a single logical action, or when you need to translate
between repository errors and the vocabulary the CLI expects.

## Qualified subdirectories and module paths

The dune file uses `(include_subdirs qualified)`.  This means each
directory becomes a module namespace inside the `kbases` library:

```
Kbases.Control.Git
Kbases.Data.Identifier
Kbases.Data.Uuid.Typeid
Kbases.Repository.Note
Kbases.Service.Kb_service
```

A new file `lib/data/foo.ml` automatically appears as
`Kbases.Data.Foo`.  A new file `lib/data/bar/baz.ml` appears as
`Kbases.Data.Bar.Baz`.  No extra dune configuration is needed as long
as the file is under `lib/`.

## Interface files

Every `.ml` file **must** have a corresponding `.mli` that documents
the public API with ocamldoc comments.  The `.mli` hides implementation
details (record fields, helper functions) and serves as the primary
reference for consumers.

## Decision checklist for new code

When you are about to add something, run through these questions:

1. **Is it a pure domain concept with invariants to enforce?**
   - Yes → Data.  Define an abstract type with a smart constructor.
   - No  → keep reading.

2. **Is it about control flow, error handling, or non-database I/O
   (filesystem, subprocesses, stdin/stdout)?**
   - Yes → Control.
   - No  → keep reading.

3. **Does it touch the database or other persistent storage?**
   - Yes → Repository (or Service if it orchestrates several repos).
   - No  → you probably need a Data module after all.

4. **Does it need to coordinate multiple repos or translate errors for
   the CLI?**
   - Yes → Service.

5. **Is it CLI argument parsing or thin wiring?**
   - It belongs in `bin/`, not here.  See `docs/bin/principles.md`.
