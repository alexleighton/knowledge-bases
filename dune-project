(lang dune 3.11)
(name knowledge-bases)
(generate_opam_files true)

(package
 (name knowledge-bases)
 (synopsis "Knowledge base management CLI for coding agents")
 (description "A CLI tool for creating and managing git-distributed knowledge bases suited for coding agents.")
 (depends
  (ocaml (>= 5.4.0))
  (dune (>= 3.20.0))
  )
)
