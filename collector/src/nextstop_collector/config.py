from functools import lru_cache
from pathlib import Path

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env",
        env_prefix="NEXTSTOP_",
        extra="ignore",
    )

    tfnsw_api_key: str = ""
    ingest_token: str = ""

    database_url: str = "sqlite:///nextstop.db"

    # Static GTFS bundles to compare against. These are the modes the Chatswood
    # corridor runs on; buses is deliberately excluded because the bundle is enormous
    # and the corridor is rail.
    gtfs_feeds: tuple[str, ...] = ("metro", "sydneytrains")
    gtfs_cache_dir: Path = Path("gtfs_cache")
    gtfs_max_age_hours: int = 24 * 7

    # Bronze plan: 60,000 calls/day, 5 calls/second.
    daily_quota: int = 60_000
    requests_per_second: float = 5.0

    # TfNSW returns intermittent 503 "quota or rate limit exceeded" well under the
    # documented limits, so retry is not optional.
    max_retries: int = 5
    backoff_base_seconds: float = 1.0
    backoff_max_seconds: float = 60.0
    request_timeout_seconds: float = 30.0
    # The GTFS bundle is tens of MB, so it needs a far longer timeout than a JSON call.
    download_timeout_seconds: float = 600.0

    # The docs say the quota counter resets at "midnight AEST". AEST is fixed UTC+10
    # but Sydney shifts to UTC+11 over summer, so the two readings differ by an hour
    # for half the year. We assume the colloquial one (Sydney local midnight); set
    # this to "Etc/GMT-10" for literal fixed UTC+10. At our call volume the
    # distinction is immaterial, but the accounting should at least be explicit.
    quota_reset_tz: str = "Australia/Sydney"

    def require_tfnsw_key(self) -> str:
        if not self.tfnsw_api_key:
            raise RuntimeError(
                "NEXTSTOP_TFNSW_API_KEY is not set. Copy .env.example to .env and fill it in."
            )
        return self.tfnsw_api_key


@lru_cache
def get_settings() -> Settings:
    return Settings()
