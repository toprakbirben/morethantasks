import os

from db import get_conn

# SQL files live next to this module so the runner works regardless of CWD.
MIGRATIONS_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "migrations")


def run_migrations():
    # Apply every migrations/*.sql file not yet recorded in schema_migrations,
    # in filename order. Each file runs in its own transaction together with the
    # record insert, so a crash mid-file never leaves it marked as applied.
    conn = get_conn()
    with conn.cursor() as cur:
        cur.execute(
            """
            CREATE TABLE IF NOT EXISTS schema_migrations (
                filename   text PRIMARY KEY,
                applied_at timestamp NOT NULL DEFAULT now()
            )
            """
        )
        conn.commit()

        cur.execute("SELECT filename FROM schema_migrations")
        applied = {row[0] for row in cur.fetchall()}

    files = sorted(f for f in os.listdir(MIGRATIONS_DIR) if f.endswith(".sql"))
    for filename in files:
        if filename in applied:
            continue
        with open(os.path.join(MIGRATIONS_DIR, filename)) as f:
            sql = f.read()
        try:
            with conn.cursor() as cur:
                cur.execute(sql)
                cur.execute(
                    "INSERT INTO schema_migrations (filename) VALUES (%s)",
                    (filename,),
                )
            conn.commit()
            print(f"Applied migration: {filename}")
        except Exception:
            # Fail loud: roll back the partial migration and re-raise so the
            # error surfaces instead of leaving the schema half-applied.
            conn.rollback()
            raise


if __name__ == "__main__":
    run_migrations()
