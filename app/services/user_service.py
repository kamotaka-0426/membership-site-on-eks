from sqlalchemy.orm import Session
from fastapi import HTTPException, status
from app import schemas, database
from app.core import security

class UserService:
    @staticmethod
    def create_user(db: Session, user: schemas.UserCreate):
        db_user = db.query(database.User).filter(database.User.email == user.email).first()
        if db_user:
            raise HTTPException(status_code=400, detail="Email already registered")
        
        hashed_pwd = security.get_password_hash(user.password)
        new_user = database.User(email=user.email, hashed_password=hashed_pwd)
        db.add(new_user)
        db.commit()
        db.refresh(new_user)
        return new_user

    @staticmethod
    def authenticate_user(db: Session, email: str, password: str):
        user = db.query(database.User).filter(database.User.email == email).first()
        if not user or not security.verify_password(password, user.hashed_password):
            return None
        return user
