# Suppressing unused-export warnings

The `check-unused.py` script detects exported symbols with no call-site in the
codebase. When a symbol is intentionally exported but cannot be traced by the
script — e.g., a value consumed via functor application — annotate the
definition line with `(* @unused-ok — <reason> *)` to suppress the warning.
The reason must explain **why** the symbol appears unused (e.g., which functor
consumes it, which external caller needs it). A bare `(* @unused-ok *)` without
a reason is not sufficient — the reader needs to understand why the suppression
is safe without chasing down the usage themselves.
