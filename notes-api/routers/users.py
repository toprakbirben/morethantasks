from fastapi import APIRouter
from passlib.hash import bcrypt

from db import get_conn
from models import LoginRequest

router = APIRouter()


@router.post("/login")
async def login(request: LoginRequest):
    user = await login_user(request.email, request.password)
    if user:
        return {
            "success": True,
            "user": {
                "id": user["id"],
                "email": user["email"]
            }
        }
    else:
        return {"success": False}


async def login_user(email: str, password: str):
    conn = get_conn()
    conn.rollback()
    with conn.cursor() as cur:
        cur.execute(
            "SELECT id, email, password_hash FROM users WHERE email = %s",
            (email,)
        )
        result = cur.fetchone()
        if result:
            user_id, user_email, stored_hash = result
            if __verify_password(password, stored_hash):
                return {"id": user_id, "email": user_email}
    return None


def __verify_password(plain_password: str, stored_hash) -> bool:
        try:
            print(bcrypt.verify(plain_password, stored_hash))
            return bcrypt.verify(plain_password, stored_hash)
        except ValueError:
            return False


@router.post("/add_user")
def add_user(req: LoginRequest):
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
        return {"success": False}


@router.delete("/delete_user")
def delete_user(req: dict):
    email = req.get("email")
    if not email:
        return {"success": False}

    conn = get_conn()
    try:
        with conn.cursor() as curr:
            curr.execute("DELETE FROM users WHERE email = %s", (email,))
            curr.execute("DELETE FROM notes WHERE user_id = (SELECT id FROM users WHERE email = %s)", (email,))
        conn.commit()
        return {"success": True}
    except Exception as e:
        conn.rollback()
        print("Delete user error:", e)
        return {"success": False}


@router.patch("/reset")
def reset_password(req: LoginRequest):
    new_hash = bcrypt.hash(req.password)

    conn = get_conn()
    with conn.cursor() as cur:
        cur.execute(
            "SELECT id FROM users WHERE email = %s",
            (req.email,)
        )
        user = cur.fetchone()

        if not user:
            return {"success": False, "message": "Email not found"}

        cur.execute(
            "UPDATE users SET password_hash = %s WHERE email = %s",
            (new_hash, req.email)
        )

    conn.commit()
    return {"success": True, "message": "Password updated"}
