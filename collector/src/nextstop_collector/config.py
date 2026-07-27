from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env",
        env_prefix="NEXTSTOP_",
        extra="ignore",
    )

    tfnsw_api_key: str = ""
    google_api_key: str = ""
    ingest_token: str = ""

    database_url: str = "sqlite:///nextstop.db"

    # Bronze plan: 60,000 calls/day, 5 calls/second.
    daily_quota: int = 60_000
    requests_per_second: float = 5.0

    # TfNSW returns intermittent 503 "quota or rate limit exceeded" well under the
    # documented limits, so retry is not optional.
    max_retries: int = 5
    backoff_base_seconds: float = 1.0
    backoff_max_seconds: float = 60.0
    request_timeout_seconds: float = 30.0

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

    def require_google_key(self) -> str:
        if not self.google_api_key:
            raise RuntimeError(
                "NEXTSTOP_GOOGLE_API_KEY is not set. Copy .env.example to .env and fill it in."
            )
        return self.google_api_key


@lru_cache
def get_settings() -> Settings:
    return Settings()
