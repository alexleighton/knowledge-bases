# `scripts/` Principles

Guiding principles for code that lives in `scripts/`.

## 1. Shellcheck

Every shell script in `scripts/` **must** pass
[ShellCheck](https://www.shellcheck.net/) with no warnings. Run it after
editing any `.sh` file:

```
shellcheck scripts/<file>.sh
```

ShellCheck catches real bugs — unquoted variables, non-portable syntax,
unreachable code — that are easy to miss in review. Treating its output as
mandatory keeps scripts correct across shells and platforms.

## 2. `find-unused.py` suppression

`find-unused.py` supports a `(* @unused-ok — <reason> *)` comment on the
definition line to suppress false positives. The annotation must include a
reason explaining why the symbol appears unused. See `docs/lib/principles.md`
§6 for details.
