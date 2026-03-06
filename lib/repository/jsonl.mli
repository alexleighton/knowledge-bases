(** JSONL file format — serialization, parsing, content hashing, and
    atomic file I/O for the snapshot sync file. *)

(** A parsed entity record from a JSONL file. *)
type entity_record =
  | Todo of { id: Data.Uuid.Typeid.t; title: Data.Title.t;
              content: Data.Content.t; status: Data.Todo.status }
  | Note of { id: Data.Uuid.Typeid.t; title: Data.Title.t;
              content: Data.Content.t; status: Data.Note.status }
  | Relation of Data.Relation.t

(** Metadata stored in the first line of a JSONL file. *)
type header = {
  version   : int;
  namespace : string;
}

(** Errors from JSONL operations. *)
type error =
  | Io_error of string
  | Parse_error of string

(** [write ~path ~namespace ~todos ~notes ~relations] serializes all
    entities to a JSONL file at [path] using an atomic temp-file rename. *)
val write :
  path:string -> namespace:string ->
  todos:Data.Todo.t list -> notes:Data.Note.t list ->
  relations:Data.Relation.t list -> (unit, error) result

(** [read_header ~path] reads only the first line of the JSONL file,
    returning the parsed header. *)
val read_header : path:string -> (header, error) result

(** [read ~path] reads the entire JSONL file, returning the header
    and all parsed entity records. *)
val read : path:string -> (header * entity_record list, error) result

(** [record_sort_key record] returns the deterministic sort key for
    [record].  This is the canonical ordering used by both [write]
    and rebuild — callers that need to sort {!entity_record} values
    should use this function rather than reimplementing the key. *)
val record_sort_key : entity_record -> string

