-- 002_crdt_and_sharing.sql
-- Section 1 (server half) of docs/superpowers/specs/2026-06-02-collaborative-editing-design.md:
-- append-only body-CRDT op log + flat note sharing.

-- Op identity mirrors the client's CharID (lamport, site_id) — same as the
-- CRDTStore.swift op_key encoding — so re-POSTing the same op is a no-op.
CREATE TABLE note_crdt_ops (
    note_id       text NOT NULL REFERENCES notes(id),
    op_type       text NOT NULL CHECK (op_type IN ('insert', 'delete')),
    char          text,
    after_lamport bigint,
    after_site_id uuid,
    lamport       bigint NOT NULL,
    site_id       uuid NOT NULL,
    server_seq    bigserial,
    PRIMARY KEY (note_id, lamport, site_id)
);

CREATE INDEX idx_crdt_ops_note_seq ON note_crdt_ops (note_id, server_seq);

CREATE TABLE note_collaborators (
    note_id  text NOT NULL REFERENCES notes(id),
    user_id  integer NOT NULL REFERENCES users(id),
    added_at timestamp without time zone NOT NULL DEFAULT now(),
    PRIMARY KEY (note_id, user_id)
);
