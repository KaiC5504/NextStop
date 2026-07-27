import os

import pytest

TEST_TOKEN = "test-token"


@pytest.fixture(scope="session", autouse=True)
def test_database(tmp_path_factory):
    """Point every cached engine/settings object at a throwaway SQLite file.

    Has to run before anything imports a session, hence session scope and autouse.
    """
    db_path = tmp_path_factory.mktemp("db") / "test.db"
    os.environ["NEXTSTOP_DATABASE_URL"] = f"sqlite:///{db_path.as_posix()}"
    os.environ["NEXTSTOP_INGEST_TOKEN"] = TEST_TOKEN
    os.environ["NEXTSTOP_TFNSW_API_KEY"] = "test-key"

    from nextstop_collector.config import get_settings
    from nextstop_collector.storage import db

    get_settings.cache_clear()
    db.get_engine.cache_clear()
    db.get_session_factory.cache_clear()
    db.init_db()
    yield


@pytest.fixture
def auth_headers() -> dict[str, str]:
    return {"X-NextStop-Token": TEST_TOKEN}
