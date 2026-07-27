from google.transit import gtfs_realtime_pb2

from nextstop_collector.tfnsw import quirks

_TripSR = gtfs_realtime_pb2.TripDescriptor
_StopSR = gtfs_realtime_pb2.TripUpdate.StopTimeUpdate


def make_entity(
    entity_id: str,
    route_id: str = "T1",
    trip_id: str = "trip-1",
    start_date: str = "20260727",
    schedule_relationship: int | None = None,
) -> gtfs_realtime_pb2.FeedEntity:
    entity = gtfs_realtime_pb2.FeedEntity()
    entity.id = entity_id
    trip = entity.trip_update.trip
    trip.trip_id = trip_id
    trip.route_id = route_id
    trip.start_date = start_date
    if schedule_relationship is not None:
        trip.schedule_relationship = schedule_relationship
    return entity


def make_feed(*entities: gtfs_realtime_pb2.FeedEntity) -> gtfs_realtime_pb2.FeedMessage:
    feed = gtfs_realtime_pb2.FeedMessage()
    feed.header.gtfs_realtime_version = "2.0"
    feed.entity.extend(entities)
    return feed


def add_stop(
    entity: gtfs_realtime_pb2.FeedEntity,
    stop_id: str,
    pickup_type: int | None = None,
    drop_off_type: int | None = None,
    schedule_relationship: int | None = None,
) -> _StopSR:
    update = entity.trip_update.stop_time_update.add()
    update.stop_id = stop_id
    if schedule_relationship is not None:
        update.schedule_relationship = schedule_relationship
    if pickup_type is not None:
        update.stop_time_properties.pickup_type = pickup_type
    if drop_off_type is not None:
        update.stop_time_properties.drop_off_type = drop_off_type
    return update


class TestNonRevenue:
    def test_rtta_routes_are_excluded(self):
        feed = make_feed(
            make_entity("a", route_id="RTTA_DEF"),
            make_entity("b", route_id="RTTA_REV"),
            make_entity("c", route_id="T1"),
        )
        kept = [e.id for e in quirks.revenue_entities(feed)]
        assert kept == ["c"]

    def test_charter_routes_excluded_when_configured(self):
        config = quirks.QuirkConfig(charter_route_ids=frozenset({"CHARTER_1"}))
        feed = make_feed(
            make_entity("a", route_id="CHARTER_1"),
            make_entity("b", route_id="T1"),
        )
        assert [e.id for e in quirks.revenue_entities(feed, config)] == ["b"]


class TestScheduleRelationship:
    def test_replacement_is_classified_as_altered(self):
        """The quirk that matters: REPLACEMENT must not fall through to 'scheduled'."""
        entity = make_entity("a", schedule_relationship=_TripSR.REPLACEMENT)
        assert quirks.classify_trip(entity) == "altered"

    def test_cancelled_and_deleted(self):
        assert (
            quirks.classify_trip(make_entity("a", schedule_relationship=_TripSR.CANCELED))
            == "cancelled"
        )
        assert (
            quirks.classify_trip(make_entity("b", schedule_relationship=_TripSR.DELETED))
            == "cancelled"
        )

    def test_default_is_scheduled(self):
        assert quirks.classify_trip(make_entity("a")) == "scheduled"


class TestPassingStops:
    def test_skipped_stop_is_not_boardable(self):
        entity = make_entity("a")
        update = add_stop(entity, "S1", schedule_relationship=_StopSR.SKIPPED)
        assert not quirks.is_boardable(update)
        assert not quirks.can_alight(update)

    def test_no_pick_up_blocks_boarding_but_allows_alighting(self):
        entity = make_entity("a")
        update = add_stop(entity, "S1", pickup_type=1)
        assert not quirks.is_boardable(update)
        assert quirks.can_alight(update)

    def test_no_set_down_blocks_alighting_but_allows_boarding(self):
        entity = make_entity("a")
        update = add_stop(entity, "S1", drop_off_type=1)
        assert quirks.is_boardable(update)
        assert not quirks.can_alight(update)

    def test_ordinary_stop_is_both(self):
        entity = make_entity("a")
        update = add_stop(entity, "S1")
        assert quirks.is_boardable(update)
        assert quirks.can_alight(update)

    def test_boardable_stops_filters_the_sequence(self):
        entity = make_entity("a")
        add_stop(entity, "S1")
        add_stop(entity, "S2", schedule_relationship=_StopSR.SKIPPED)
        add_stop(entity, "S3", pickup_type=1)
        add_stop(entity, "S4")
        assert [u.stop_id for u in quirks.boardable_stops(entity)] == ["S1", "S4"]


class TestDedupe:
    def test_same_trip_in_two_feeds_appears_once(self):
        sydney_trains = make_feed(make_entity("st-1", trip_id="shared", route_id="T1"))
        nsw_trains = make_feed(make_entity("nsw-1", trip_id="shared", route_id="T1"))
        merged = quirks.dedupe_across_feeds([sydney_trains, nsw_trains])
        assert [e.id for e in merged] == ["st-1"]

    def test_distinct_trips_are_all_kept(self):
        feed_a = make_feed(make_entity("a", trip_id="t1"))
        feed_b = make_feed(make_entity("b", trip_id="t2"))
        merged = quirks.dedupe_across_feeds([feed_a, feed_b])
        assert [e.id for e in merged] == ["a", "b"]

    def test_same_trip_id_on_different_days_is_not_a_duplicate(self):
        feed = make_feed(
            make_entity("a", trip_id="t1", start_date="20260727"),
            make_entity("b", trip_id="t1", start_date="20260728"),
        )
        assert len(quirks.dedupe_across_feeds([feed])) == 2

    def test_non_revenue_is_dropped_during_merge(self):
        feed = make_feed(
            make_entity("a", route_id="RTTA_DEF", trip_id="t1"),
            make_entity("b", route_id="T1", trip_id="t2"),
        )
        assert [e.id for e in quirks.dedupe_across_feeds([feed])] == ["b"]
