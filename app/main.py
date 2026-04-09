import logging
import json
from contextlib import asynccontextmanager
from fastapi import FastAPI, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from starlette.middleware.base import BaseHTTPMiddleware
from app.database import create_tables
from app.core.config import settings
from app.routers import auth, posts

# --- ロギング設定 ---
class JsonFormatter(logging.Formatter):
    def format(self, record):
        return json.dumps({
            "timestamp": self.formatTime(record),
            "level": record.levelname,
            "message": record.getMessage(),
            "module": record.module
        })

handler = logging.StreamHandler()
handler.setFormatter(JsonFormatter())
logger = logging.getLogger("my_app")
logger.addHandler(handler)
logger.setLevel(logging.INFO)

@asynccontextmanager
async def lifespan(app: FastAPI):
    # 起動時にテーブルを作成
    create_tables()
    yield

app = FastAPI(title=settings.PROJECT_NAME, lifespan=lifespan)

# --- カスタムミドルウェア ---
class OriginVerifyMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next):
        if request.url.path == "/health":
            return await call_next(request)
        if settings.ORIGIN_VERIFY_SECRET:
            header_value = request.headers.get("X-Origin-Verify", "")
            if header_value != settings.ORIGIN_VERIFY_SECRET:
                raise HTTPException(status_code=403, detail="Direct access is not allowed")
        return await call_next(request)

app.add_middleware(OriginVerifyMiddleware)
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.ALLOWED_ORIGINS,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# --- ルーター登録 ---
app.include_router(auth.router)
app.include_router(posts.router)

@app.get("/health")
async def health_check():
    return {"status": "ok", "project": settings.PROJECT_NAME}

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
