(lang dune 3.11)
(name knowledge-bases)
(generate_opam_files true)

(package
 (name knowledge-bases)
 (synopsis "Knowledge base management CLI for coding agents")
 (description "A CLI tool for creating and managing git-distributed knowledge bases suited for coding agents.")
 (depends
  (ocaml (>= "5.3.0"))
  (dune (>= "3.20.2"))
  (ppx_deriving (>= "6.1.1"))
  (ppx_expect (and (= "v0.17.3") :with-test))
  (ppx_inline_test (and (= "v0.17.1") :with-test))
  str
  )
)

