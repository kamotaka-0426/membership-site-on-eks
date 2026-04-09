from sqlalchemy.orm import Session
from fastapi import HTTPException, status
from app import schemas, database
from app.core.config import settings

class PostService:
    @staticmethod
    def get_posts(db: Session):
        return db.query(database.Post).all()

    @staticmethod
    def create_post(db: Session, post: schemas.PostCreate, user_id: int):
        new_post = database.Post(title=post.title, content=post.content, owner_id=user_id)
        db.add(new_post)
        db.commit()
        db.refresh(new_post)
        return new_post

    @staticmethod
    def delete_post(db: Session, post_id: int, current_user: database.User):
        post = db.query(database.Post).filter(database.Post.id == post_id).first()
        if not post:
            raise HTTPException(status_code=404, detail="Post not found")
        
        is_owner = (post.owner_id == current_user.id)
        is_admin = (current_user.email == settings.ADMIN_EMAIL)
        
        if not (is_owner or is_admin):
            raise HTTPException(status_code=403, detail="Not authorized to delete this post")
            
        db.delete(post)
        db.commit()
        return {"message": "Post deleted successfully"}
