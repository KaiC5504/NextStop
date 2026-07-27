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

    # Static GTFS bundles to compare against — the modes the Chatswood-to-USyd trip
    # actually uses. buses is ~99 MB and slow to parse, but the bus leg is where the
    # published timetable is most likely to be wrong, so excluding it would drop the
    # most interesting half of the result.
    gtfs_feeds: tuple[str, ...] = ("metro", "sydneytrains", "buses")

    # Feeds sit on different API versions and it is not cosmetic. Metro moved to v2
    # when the City & Southwest section opened; v1/gtfs/schedule/metro still answers
    # 200 but its calendar expired 2024-12-26 and it carries only the 13 North West
    # stations, so it would silently yield zero scheduled departures for the whole
    # Chatswood-to-city corridor. sydneytrains has no v2 — it 404s.
    gtfs_feed_versions: dict[str, str] = {"metro": "v2"}
    gtfs_default_version: str = "v1"

    gtfs_cache_dir: Path = Path("gtfs_cache")
    gtfs_max_age_hours: int = 24 * 7

    def feed_version(self, feed: str) -> str:
        return self.gtfs_feed_versions.get(feed, self.gtfs_default_version)

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
        # Stripped because a .env written on Windows and copied to a Linux box keeps its
        # CRLF endings, and systemd's EnvironmentFile hands the trailing \r straight
        # through into the value. The result is a 401 that looks like a bad key.
        key = self.tfnsw_api_key.strip()
        if not key:
            raise RuntimeError(
                "NEXTSTOP_TFNSW_API_KEY is not set. Copy .env.example to .env and fill it in."
            )
        return key


@lru_cache
def get_settings() -> Settings:
    return Settings()
