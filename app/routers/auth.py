from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.security import OAuth2PasswordRequestForm
from sqlalchemy.orm import Session
from app import schemas
from app.core import security
from app.services.user_service import UserService

router = APIRouter(prefix="/auth", tags=["auth"])

@router.post("/register", response_model=schemas.UserResponse)
def register(user: schemas.UserCreate, db: Session = Depends(security.get_db)):
    return UserService.create_user(db, user)

@router.post("/login", response_model=schemas.Token)
def login(form_data: OAuth2PasswordRequestForm = Depends(), db: Session = Depends(security.get_db)):
    user = UserService.authenticate_user(db, form_data.username, form_data.password)
    if not user:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Incorrect email or password",
            headers={"WWW-Authenticate": "Bearer"},
        )
    
    access_token = security.create_access_token(data={"sub": str(user.id)})
    return {"access_token": access_token, "token_type": "bearer"}
