from fastapi import APIRouter, Depends, status
from sqlalchemy.orm import Session
from app import schemas, database
from app.core import security
from app.services.post_service import PostService

router = APIRouter(prefix="/posts", tags=["posts"])

@router.get("/", response_model=list[schemas.PostResponse])
def read_posts(db: Session = Depends(security.get_db)):
    return PostService.get_posts(db)

@router.post("/", response_model=schemas.PostResponse)
def create_post(
    post: schemas.PostCreate, 
    db: Session = Depends(security.get_db), 
    current_user: database.User = Depends(security.get_current_user)
):
    return PostService.create_post(db, post, current_user.id)

@router.delete("/{post_id}")
def delete_post(
    post_id: int, 
    db: Session = Depends(security.get_db), 
    current_user: database.User = Depends(security.get_current_user)
):
    return PostService.delete_post(db, post_id, current_user)
