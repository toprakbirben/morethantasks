from fastapi import APIRouter, HTTPException

from db import get_conn
from models import LoginRequest

router = APIRouter()


@router.post("/sessions")
async def create_session(request: LoginRequest):
    user = await login_user(request.email, request.password)
    if user:
        return {
            "user": {
                "id": user["id"],
                "email": user["email"]
            }
        }
    raise HTTPException(status_code=401, detail="Invalid email or password")


async def login_user(email: str, password: str):
    # Verify the password inside Postgres via pgcrypto: crypt() re-hashes the
    # supplied password with the stored hash's own salt, so the comparison
    # succeeds only on a match. Keeps verification consistent with create_user.
    conn = get_conn()
    conn.rollback()
    with conn.cursor() as cur:
        cur.execute(
            "SELECT id, email FROM users "
            "WHERE email = %s AND password_hash = crypt(%s, password_hash)",
            (email, password)
        )
        result = cur.fetchone()
        if result:
            user_id, user_email = result
            return {"id": user_id, "email": user_email}
    return None


@router.post("/users", status_code=201)
def create_user(req: LoginRequest):
    conn = get_conn()
    try:
        with conn.cursor() as curr:
            curr.execute(
                """
                INSERT INTO users (email, password_hash)
                VALUES (%s, crypt(%s, gen_salt('bf')))
                """,
                (req.email, req.password)
            )
        conn.commit()
        return {"success": True}
    except Exception as e:
        conn.rollback()
        print("Error creating user:", e)
        raise HTTPException(status_code=409, detail="Could not create user")


@router.delete("/users/{user_id}", status_code=204)
def delete_user(user_id: int):
    conn = get_conn()
    try:
        with conn.cursor() as curr:
            # Delete the user's notes first to respect the user_id foreign key.
            curr.execute("DELETE FROM notes WHERE user_id = %s", (user_id,))
            curr.execute("DELETE FROM users WHERE id = %s", (user_id,))
        conn.commit()
        return None
    except Exception as e:
        conn.rollback()
        print("Delete user error:", e)
        raise HTTPException(status_code=500, detail="Could not delete user")


@router.post("/users/password-reset")
def reset_password(req: LoginRequest):
    conn = get_conn()
    with conn.cursor() as cur:
        cur.execute(
            "SELECT id FROM users WHERE email = %s",
            (req.email,)
        )
        user = cur.fetchone()

        if not user:
            raise HTTPException(status_code=404, detail="Email not found")

        # Hash with pgcrypto (bcrypt), matching create_user and login_user.
        cur.execute(
            "UPDATE users SET password_hash = crypt(%s, gen_salt('bf')) WHERE email = %s",
            (req.password, req.email)
        )

    conn.commit()
    return {"success": True, "message": "Password updated"}
