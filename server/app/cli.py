from __future__ import annotations

import argparse
import getpass

from sqlalchemy import select

from .database import db
from .models import User
from .security import hash_secret


def create_admin(username: str, password: str | None, pin: str | None) -> None:
    password = password or getpass.getpass("家长密码: ")
    pin = pin or getpass.getpass("4 位家长 PIN: ")
    if len(password) < 10:
        raise SystemExit("家长密码至少 10 位")
    if len(pin) != 4 or not pin.isdigit():
        raise SystemExit("家长 PIN 必须是 4 位数字")
    db.create_all()
    with db.session_factory() as session:
        if session.scalar(select(User).where(User.username == username)):
            raise SystemExit("账号已存在")
        session.add(User(username=username, password_hash=hash_secret(password), pin_hash=hash_secret(pin)))
        session.commit()
    print(f"已创建家长账号: {username}")


def main() -> None:
    parser = argparse.ArgumentParser(description="勇敢成长服务端管理工具")
    subparsers = parser.add_subparsers(dest="command", required=True)
    create = subparsers.add_parser("create-admin")
    create.add_argument("--username", default="parent")
    create.add_argument("--password")
    create.add_argument("--pin")
    args = parser.parse_args()
    if args.command == "create-admin":
        create_admin(args.username, args.password, args.pin)


if __name__ == "__main__":
    main()

