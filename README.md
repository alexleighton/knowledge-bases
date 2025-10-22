# Knowledge Bases

A CLI tool for creating and managing git-distributed knowledge bases suited for coding agents.

# Features

No features right now.

MVP Featureset to be built:

  * Stable "database" file which can be clearly `diff`'d by git.
  * Structured issues, uniquely identified, and capable of being related to eachother. These will represent agent-determined TODOs, tracked externally from the agent's context, to free up space in context and keep the agent's attention focused.
  * Structured notes, uniquely identified, for capturing research, ideas, and decisions.
  * opam-distributed binary, let's say `bs`, for basic issue and note management.
    * E.g. `bs init`, `bs list`, `bs show`, `bs create`, `bs update`, `bs resolve`.

# Development

**Build:**

```
$ dune build
```

**Invoke Executable:**

```
$ dune exec bs
```

# License

This project is licensed under the terms of the MIT license. See LICENSE.txt
