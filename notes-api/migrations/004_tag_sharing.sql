-- 004_tag_sharing.sql
-- Promotes notes.tag (a plain string) to a first-class `tags` entity so a tag
-- can be shared: renaming a tag now propagates to everyone it's shared with,
-- and a tag can carry its own collaborators (see tag_collaborators, which
-- mirrors note_collaborators/003's pending/accepted flow).
--
-- Only root notes carry a tag (child notes clear theirs on reparent -- see
-- NotesViewModel.promote in the client), so notes.tag_id is nullable.

CREATE TABLE tags (
    id         text NOT NULL PRIMARY KEY,
    owner_id   integer NOT NULL REFERENCES users(id),
    name       text NOT NULL,
    created_at timestamp without time zone NOT NULL DEFAULT now(),
    UNIQUE (owner_id, name)
);

ALTER TABLE notes ADD COLUMN tag_id text REFERENCES tags(id);

-- Backfill: one tags row per distinct (owner, tag string) pair in use, then
-- point notes at it.
INSERT INTO tags (id, owner_id, name)
SELECT gen_random_uuid()::text, user_id, tag
FROM notes
WHERE tag IS NOT NULL AND tag <> ''
GROUP BY user_id, tag;

UPDATE notes
SET tag_id = tags.id
FROM tags
WHERE tags.owner_id = notes.user_id AND tags.name = notes.tag;

ALTER TABLE notes DROP COLUMN tag;

CREATE TABLE tag_collaborators (
    tag_id   text NOT NULL REFERENCES tags(id),
    user_id  integer NOT NULL REFERENCES users(id),
    status   text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'accepted')),
    added_at timestamp without time zone NOT NULL DEFAULT now(),
    PRIMARY KEY (tag_id, user_id)
);
