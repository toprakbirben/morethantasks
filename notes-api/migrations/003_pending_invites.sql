-- 003_pending_invites.sql
-- Invites now require the invitee's consent: a note_collaborators row starts
-- 'pending' and only becomes 'accepted' once the invitee responds. Existing
-- rows (created before this migration, when invite = immediate access)
-- default to 'accepted' so nobody already sharing a note loses access.

ALTER TABLE note_collaborators ADD COLUMN status text NOT NULL DEFAULT 'accepted';
ALTER TABLE note_collaborators ADD CONSTRAINT note_collaborators_status_check
    CHECK (status IN ('pending', 'accepted'));
