import os
import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool
from fastapi.testclient import TestClient

# Set environment variables before importing the app to prevent RuntimeError in auth.py
os.environ["JWT_SECRET_KEY"] = "test-secret-key-do-not-use-in-production"
os.environ["ADMIN_EMAIL"] = "admin@example.com"

# Patch the database engine to use in-memory SQLite before main.py is imported
from app import database

_test_engine = create_engine(
    "sqlite:///:memory:",
    connect_args={"check_same_thread": False},
    poolclass=StaticPool,
)
_TestSessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=_test_engine)
database.engine = _test_engine  # redirect create_tables() to SQLite

# Import app after patching (create_tables() runs against SQLite)
from app.main import app
from app.core.security import get_db

database.Base.metadata.create_all(bind=_test_engine)


def _override_get_db():
    db = _TestSessionLocal()
    try:
        yield db
    finally:
        db.close()


app.dependency_overrides[get_db] = _override_get_db


@pytest.fixture(autouse=True)
def reset_db():
    """Reset tables before each test to keep tests isolated."""
    yield
    database.Base.metadata.drop_all(bind=_test_engine)
    database.Base.metadata.create_all(bind=_test_engine)


@pytest.fixture
def client():
    return TestClient(app)


@pytest.fixture
def registered_user(client):
    client.post("/auth/register", json={"email": "user@example.com", "password": "password123"})
    return {"email": "user@example.com", "password": "password123"}


@pytest.fixture
def auth_headers(client, registered_user):
    res = client.post("/auth/login", data={
        "username": registered_user["email"],
        "password": registered_user["password"],
    })
    token = res.json()["access_token"]
    return {"Authorization": f"Bearer {token}"}
