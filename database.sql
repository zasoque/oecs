-- OECS language-expression graph schema (PostgreSQL 15+)
-- A node is an observed expression, never an abstract, numbered meaning.

CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE people (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  username TEXT NOT NULL UNIQUE CHECK (username ~ '^[A-Za-z0-9_.-]{3,64}$'),
  display_name TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE languages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  identifier TEXT NOT NULL UNIQUE CHECK (identifier ~ '^[a-z][a-z0-9-]{1,62}$'),
  name TEXT NOT NULL,
  native_name TEXT,
  creator_id UUID REFERENCES people(id) ON DELETE SET NULL,
  description TEXT,
  status TEXT NOT NULL DEFAULT 'active'
    CHECK (status IN ('draft', 'active', 'archived')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE sources (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  source_type TEXT NOT NULL CHECK (source_type IN
    ('language_creator', 'grammar_book', 'dictionary', 'published_text',
     'community_discussion', 'historical_document', 'external_source', 'other')),
  title TEXT NOT NULL,
  author TEXT,
  url TEXT,
  publication_date DATE,
  license TEXT,
  notes TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Dates can be omitted; certainty makes approximate historical claims explicit.
CREATE TABLE language_versions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  language_id UUID NOT NULL REFERENCES languages(id) ON DELETE CASCADE,
  version TEXT NOT NULL,
  valid_from DATE,
  valid_until DATE,
  temporal_certainty TEXT NOT NULL DEFAULT 'exact'
    CHECK (temporal_certainty IN ('exact', 'approximate', 'before', 'after', 'unknown')),
  description TEXT,
  grammar_source_id UUID REFERENCES sources(id) ON DELETE SET NULL,
  orthography_source_id UUID REFERENCES sources(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (language_id, version),
  CHECK (valid_until IS NULL OR valid_from IS NULL OR valid_until >= valid_from)
);

-- The stable node identity.  Do not place a canonical meaning/gloss here.
CREATE TABLE expressions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  language_id UUID NOT NULL REFERENCES languages(id) ON DELETE RESTRICT,
  expression_type TEXT NOT NULL CHECK (expression_type IN
    ('word', 'compound', 'phrase', 'idiom', 'clause', 'sentence', 'other')),
  script TEXT,
  created_by UUID REFERENCES people(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Append-only editorial history.  The newest row is the current presentation.
CREATE TABLE expression_revisions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  expression_id UUID NOT NULL REFERENCES expressions(id) ON DELETE CASCADE,
  revision_number INTEGER NOT NULL CHECK (revision_number > 0),
  text TEXT NOT NULL CHECK (length(btrim(text)) > 0),
  normalized_text TEXT NOT NULL CHECK (length(btrim(normalized_text)) > 0),
  language_version_id UUID REFERENCES language_versions(id) ON DELETE SET NULL,
  usage_status TEXT NOT NULL DEFAULT 'standard' CHECK (usage_status IN
    ('standard', 'colloquial', 'dialect', 'archaic', 'obsolete', 'nonstandard',
     'experimental', 'incorrect')),
  valid_from DATE,
  valid_until DATE,
  temporal_certainty TEXT NOT NULL DEFAULT 'exact'
    CHECK (temporal_certainty IN ('exact', 'approximate', 'before', 'after', 'unknown')),
  author_id UUID REFERENCES people(id) ON DELETE SET NULL,
  source_id UUID REFERENCES sources(id) ON DELETE SET NULL,
  change_summary TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (expression_id, revision_number),
  CHECK (valid_until IS NULL OR valid_from IS NULL OR valid_until >= valid_from)
);

CREATE INDEX expression_revisions_text_search_idx
  ON expression_revisions USING gin (to_tsvector('simple', normalized_text));
CREATE INDEX expression_revisions_expression_idx ON expression_revisions (expression_id, revision_number DESC);

-- Relation types live in data rather than an enum so communities can extend them.
CREATE TABLE relation_types (
  code TEXT PRIMARY KEY CHECK (code ~ '^[a-z][a-z_]{1,63}$'),
  is_symmetric BOOLEAN NOT NULL DEFAULT FALSE,
  description TEXT NOT NULL
);

INSERT INTO relation_types (code, is_symmetric, description) VALUES
  ('translation', false, 'A context-dependent translation relation'),
  ('paraphrase', true, 'Alternative wording with comparable content'),
  ('synonym', true, 'Near-interchangeable expression'),
  ('near_synonym', true, 'Similar but not interchangeable expression'),
  ('related', true, 'Related expression without stronger claim'),
  ('antonym', true, 'Contrastive expression'),
  ('historical_predecessor', false, 'Earlier expression leading to another'),
  ('historical_successor', false, 'Later expression descended from another'),
  ('variant', true, 'General variant'),
  ('dialect_variant', true, 'Dialectal variant'),
  ('orthographic_variant', true, 'Spelling or script variant'),
  ('formal_variant', true, 'Formal-register variant'),
  ('colloquial_variant', true, 'Colloquial-register variant');

-- A graph edge. Cycles are intentionally permitted.
CREATE TABLE expression_relations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  source_expression_id UUID NOT NULL REFERENCES expressions(id) ON DELETE RESTRICT,
  target_expression_id UUID NOT NULL REFERENCES expressions(id) ON DELETE RESTRICT,
  relation_type_code TEXT NOT NULL REFERENCES relation_types(code) ON DELETE RESTRICT,
  direction TEXT NOT NULL DEFAULT 'directed' CHECK (direction IN ('directed', 'symmetric')),
  language_version_id UUID REFERENCES language_versions(id) ON DELETE SET NULL,
  valid_from DATE,
  valid_until DATE,
  temporal_certainty TEXT NOT NULL DEFAULT 'exact'
    CHECK (temporal_certainty IN ('exact', 'approximate', 'before', 'after', 'unknown')),
  created_by UUID REFERENCES people(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CHECK (source_expression_id <> target_expression_id),
  CHECK (valid_until IS NULL OR valid_from IS NULL OR valid_until >= valid_from)
);
CREATE INDEX expression_relations_source_idx ON expression_relations (source_expression_id);
CREATE INDEX expression_relations_target_idx ON expression_relations (target_expression_id);

-- Revisions preserve contested/corrected relationship claims and their evidence.
CREATE TABLE relation_revisions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  relation_id UUID NOT NULL REFERENCES expression_relations(id) ON DELETE CASCADE,
  revision_number INTEGER NOT NULL CHECK (revision_number > 0),
  status TEXT NOT NULL DEFAULT 'proposed' CHECK (status IN ('proposed', 'accepted', 'rejected', 'superseded')),
  confidence NUMERIC(3,2) CHECK (confidence IS NULL OR confidence BETWEEN 0 AND 1),
  semantic_similarity TEXT CHECK (semantic_similarity IN ('identical', 'very_similar', 'similar', 'partially_overlapping', 'related', 'different')),
  pragmatic_similarity TEXT CHECK (pragmatic_similarity IN ('identical', 'very_similar', 'similar', 'partially_overlapping', 'related', 'different')),
  register_similarity TEXT CHECK (register_similarity IN ('identical', 'very_similar', 'similar', 'partially_overlapping', 'related', 'different')),
  structural_similarity TEXT CHECK (structural_similarity IN ('identical', 'very_similar', 'similar', 'partially_overlapping', 'related', 'different')),
  notes TEXT,
  author_id UUID REFERENCES people(id) ON DELETE SET NULL,
  source_id UUID REFERENCES sources(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (relation_id, revision_number)
);

CREATE TABLE discussions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  target_type TEXT NOT NULL CHECK (target_type IN
    ('language', 'language_version', 'expression', 'expression_revision', 'relation', 'relation_revision')),
  target_id UUID NOT NULL,
  title TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'resolved', 'closed')),
  created_by UUID REFERENCES people(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  resolved_at TIMESTAMPTZ,
  resolution TEXT CHECK (resolution IS NULL OR resolution IN ('accepted', 'rejected', 'partially_accepted', 'no_change')),
  CHECK ((status = 'resolved') = (resolved_at IS NOT NULL))
);

CREATE INDEX discussions_target_idx ON discussions (target_type, target_id);

CREATE TABLE discussion_comments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  discussion_id UUID NOT NULL REFERENCES discussions(id) ON DELETE CASCADE,
  author_id UUID REFERENCES people(id) ON DELETE SET NULL,
  body TEXT NOT NULL CHECK (length(btrim(body)) > 0),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Convenient current view; revisions remain the authoritative history.
CREATE VIEW current_expression_revisions AS
SELECT DISTINCT ON (expression_id) *
FROM expression_revisions
ORDER BY expression_id, revision_number DESC;

CREATE VIEW current_relation_revisions AS
SELECT DISTINCT ON (relation_id) *
FROM relation_revisions
ORDER BY relation_id, revision_number DESC;
