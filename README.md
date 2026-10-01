# The On-Line Encyclopedia of Constructed Language Sentences (OECS)

OECS is a collaborative wiki and corpus for constructed languages. It records real expressions—from
single words to full sentences—and the relationships between those expressions across languages,
versions, and time.

It is deliberately **not** a database of fixed, numbered meanings. An expression such as Korean
`생각`, Japanese `思い`, and a conlang expression are independent nodes. Translation, paraphrase,
synonymy, historical succession, and other claims are separately recorded as graph edges. That
allows multiple valid translations, directional translation, and cycles without treating English (or
any other language) as the absolute source.

## Database schema

The PostgreSQL schema is in [database.sql](database.sql). It provides:

- stable `languages`, `people`, and evidence `sources`;
- `expressions` as identity-only graph nodes, with append-only `expression_revisions` for text,
  standardness, sources, language version, and temporal claims;
- `expression_relations` plus append-only `relation_revisions` for directional or symmetric graph
  edges and evidence-backed similarity assessments;
- `language_versions` for grammar/orthography norms at a point in a language's history; and
- `discussions` and `discussion_comments` to preserve review and resolution history.

The schema permits cycles such as `A → B → C → A`. It intentionally has no `meaning` table,
`meaning_id`, `original_sentence_id`, or serialized translation list.

### Load the schema

Requires PostgreSQL 15+ and permission to install the `pgcrypto` extension:

```sh
createdb oecs
psql -d oecs -f database.sql
```

`current_expression_revisions` and `current_relation_revisions` are read-only convenience views; the
revision tables remain the complete audit trail. Applications should add new revisions rather than
overwriting historical rows.

### Relationship model

`relation_types` seeds the initial vocabulary: `translation`, `paraphrase`, `synonym`,
`near_synonym`, `related`, `antonym`, historical predecessor/successor, and register, dialect, or
orthographic variants. It is a table—not an enum—so communities can add types later. Similarity is
stored per axis (`semantic`, `pragmatic`, `register`, `structural`) on the relation revision, using
interpretable levels rather than one misleading aggregate score.

> Note: polymorphic discussion targets cannot be fully enforced by a conventional SQL foreign key.
> The service layer must validate that `target_id` exists for its `target_type`.

## REST API Endpoints

Base URL: `/api/v1`.

The complete machine-readable contract is [openapi.yaml](openapi.yaml), written in OpenAPI 3.1.
Responses use JSON and collection endpoints use cursor pagination (`items`, `next_cursor`). Mutating
endpoints require a bearer token; the authenticated person becomes the revision or discussion
author.

| Method         | Path                                    | Purpose                                             |
| -------------- | --------------------------------------- | --------------------------------------------------- |
| `GET`, `POST`  | `/languages`                            | List or create languages                            |
| `GET`, `PATCH` | `/languages/{languageId}`               | Read or change language metadata                    |
| `GET`, `POST`  | `/languages/{languageId}/versions`      | List or record norms/versions                       |
| `GET`, `POST`  | `/expressions`                          | Search expressions or create a node with revision 1 |
| `GET`          | `/expressions/{expressionId}`           | Read a node and its current revision                |
| `GET`, `POST`  | `/expressions/{expressionId}/revisions` | Inspect or append expression history                |
| `GET`, `POST`  | `/relations`                            | Query or create graph edges                         |
| `GET`, `POST`  | `/relations/{relationId}/revisions`     | Inspect or append evidence/assessment               |
| `GET`          | `/expression-graph`                     | Bounded graph traversal from an expression          |
| `GET`, `POST`  | `/discussions`                          | List or open a target-bound discussion              |
| `PATCH`        | `/discussions/{discussionId}`           | Resolve or close a discussion                       |
| `POST`         | `/discussions/{discussionId}/comments`  | Add a preserved comment                             |

`POST /expressions` and `POST /relations` create the node/edge and its first revision atomically.
There is deliberately no endpoint to replace expression text or delete its history. To correct a
claim, append a revision with an appropriate status; to represent a genuinely different historical
form, create a distinct expression and link it with a historical relation.

### People

Person resources provide information about OECS contributors.

| Namespace    | Type   | Description                               | Constraints |
| ------------ | ------ | ----------------------------------------- | ----------- |
| id           | string | A unique identifier for the user.         | PK          |
| username     | string | The username of the user.                 |             |
| display_name | string | Optional public display name.             |             |
| created_at   | string | The date and time the person was created. |             |

### Languages

Language resources provide information about the constructed languages available in the OECS
database.

| Namespace   | Type   | Description                                       | Constraints |
| ----------- | ------ | ------------------------------------------------- | ----------- |
| id          | string | A unique identifier for the constructed language. | PK          |
| identifier  | string | Stable, human-readable identifier.                | Unique      |
| name        | string | The name of the constructed language.             |             |
| native_name | string | Name in its own language/script.                  |             |
| created_at  | string | The date and time the language was created.       |             |
| updated_at  | string | The date and time the language was last updated.  |             |

GET /languages/:id

### Expressions

Expressions encompass words, compounds, phrases, idioms, clauses, and sentences. Text belongs to a
revision; an expression ID never encodes meaning.

| Namespace       | Type   | Description                                                | Constraints |
| --------------- | ------ | ---------------------------------------------------------- | ----------- |
| id              | string | Stable identifier for an expression node.                  | PK          |
| language_id     | string | Language containing the expression.                        | FK          |
| expression_type | string | word, compound, phrase, idiom, clause, sentence, or other. |             |
| created_at      | string | The date and time the expression was created.              |             |

GET /expressions

GET /expressions?language_id=:language_id&text=:text&type=:expression_type

GET /expressions/:id

### Relations

Relations are edges between expressions. A translation is not inherently symmetric, while a synonym
may be marked symmetric. `GET /relations?expression_id=:id` returns both incoming and outgoing
edges; it must not assume that a graph has no cycles.
