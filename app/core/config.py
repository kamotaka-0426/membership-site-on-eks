import os
from typing import List, Union
from pydantic import field_validator
from pydantic_settings import BaseSettings

class Settings(BaseSettings):
    PROJECT_NAME: str = "Membership Blog"
    SECRET_KEY: str = "placeholder-secret-key"
    ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 30
    
    DB_USER: str = "postgres"
    DB_PASSWORD: str = ""
    DB_HOST: str = "localhost"
    DB_NAME: str = "membership_db"
    
    # 柔軟に文字列またはリストで受け取る
    ALLOWED_ORIGINS: Union[str, List[str]] = "http://localhost:5173"
    ORIGIN_VERIFY_SECRET: str = ""
    ADMIN_EMAIL: str = ""

    @field_validator("ALLOWED_ORIGINS", mode="before")
    @classmethod
    def assemble_cors_origins(cls, v: Union[str, List[str]]) -> List[str]:
        if isinstance(v, str) and not v.startswith("["):
            return [i.strip() for i in v.split(",")]
        elif isinstance(v, (list, str)):
            import json
            if isinstance(v, str):
                return json.loads(v)
            return v
        raise ValueError(v)

    @property
    def DATABASE_URL(self) -> str:
        return f"postgresql://{self.DB_USER}:{self.DB_PASSWORD}@{self.DB_HOST}/{self.DB_NAME}"

    class Config:
        env_file = ".env"
        # 大文字小文字を区別しない
        case_sensitive = False

settings = Settings()
