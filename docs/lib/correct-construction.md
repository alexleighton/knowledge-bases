# Correct Construction

A pattern for modeling data in `lib/`. When defining domain types and value
objects (especially in Data modules), follow these three practices:

1. **Validate constituent data on construction.** Route all value construction
   through a single function that checks whether the input is within the valid
   subset. If not, raise (e.g. `Invalid_argument`) immediately — fail fast
   rather than carrying invalid data to explode far from the site of the
   problem. This maintains the invariant that all data in the program is
   meaningful.

2. **Immutable values.** By default, values do not change after creation.
   Immutability guards against invalidity-through-state-change and eliminates
   the complexity of tracing state through a value's lifetime. In OCaml this
   is natural; in concurrent contexts it is essential.

3. **Encapsulate primitive types.** Avoid using raw primitives (strings,
   ints, `Map<K,V>`) where a domain concept exists. Model the concept with
   a dedicated type that hides the primitive and attaches semantics. This
   discourages [Primitive Obsession](https://refactoring.guru/smells/primitive-obsession),
   encourages [domain-driven modeling](https://en.wikipedia.org/wiki/Domain-driven_design),
   and prevents the proliferation of DTOs and untyped argument soup.

## Payoff

Under this practice, anywhere in the program you are handed some data, you know
it is meaningful (and not bugged) because it can only be constructed in a
semantic-upholding way and is immutable. You know you are protected to use the
data only in semantically meaningful ways, since the data has been encapsulated
(e.g. you cannot access the time of a datetime without engaging with the
timezone).

## Further reading

* [Fail fast](https://martinfowler.com/ieeeSoftware/failFast.pdf)
* [Invariants](https://en.wikipedia.org/wiki/Invariant_(mathematics))
