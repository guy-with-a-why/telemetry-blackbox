-- The tables frames land in. The schema Job runs this in the blackbox
-- database, and clickhouse-check runs it in a scratch one. Every statement
-- is safe to run again. Changing a table that exists is a migration, written
-- as an ALTER below, never an edit to its CREATE.

-- Every delivery of every frame, as Spate inserts it, duplicates included.
-- (partition, offset) is where the gateway's record sits in telemetry.raw.
-- Redpanda gives each frame one offset, so every redelivery of a frame
-- carries the same one. received_at is the gateway's clock, also in the
-- record, so it's the same on every delivery too. inserted_at is
-- ClickHouse's own clock, so it isn't. bbcheck counts duplicates here, and
-- seven days outlives any drill report.
CREATE TABLE IF NOT EXISTS frames_raw
(
    boot_id      UUID,
    system_id    UInt8,
    component_id UInt8,
    -- MAVLink's sequence number, which wraps at 255. It counts gaps, but
    -- can't tell frame 1 from frame 257.
    seq          UInt8,
    msg_id       UInt32,
    partition    UInt16,
    offset       UInt64 CODEC(Delta, ZSTD),
    received_at  DateTime64(6, 'UTC') CODEC(Delta, ZSTD),
    inserted_at  DateTime64(6, 'UTC') DEFAULT now64(6) CODEC(Delta, ZSTD),
    payload      String CODEC(ZSTD),
    -- Lets the rollup's refresh skip parts with nothing new.
    INDEX inserted_at_minmax inserted_at TYPE minmax GRANULARITY 1
)
ENGINE = MergeTree
PARTITION BY toDate(received_at)
ORDER BY (boot_id, system_id, received_at, partition, offset)
TTL toDateTime(received_at) + INTERVAL 7 DAY;

-- One row per frame, eventually. A part is immutable once written, so a
-- duplicate isn't found when it's inserted. It goes when a background merge
-- puts it in the same part as the first copy, and keeps the last one
-- inserted. Until then, a query needs FINAL to see one row per frame.
--
-- (partition, offset) makes the key unique. The columns before it only ever
-- have one value for a given offset, so they don't change what counts as a
-- duplicate. They put a flight's frames side by side and in order on disk. A
-- merge only meets rows in the same partition, and both copies share
-- received_at, so they always do.
CREATE TABLE IF NOT EXISTS frames
(
    boot_id      UUID,
    system_id    UInt8,
    component_id UInt8,
    seq          UInt8,
    msg_id       UInt32,
    partition    UInt16,
    offset       UInt64 CODEC(Delta, ZSTD),
    received_at  DateTime64(6, 'UTC') CODEC(Delta, ZSTD),
    inserted_at  DateTime64(6, 'UTC') CODEC(Delta, ZSTD),
    payload      String CODEC(ZSTD)
)
ENGINE = ReplacingMergeTree
PARTITION BY toDate(received_at)
ORDER BY (boot_id, system_id, received_at, partition, offset)
TTL toDateTime(received_at) + INTERVAL 30 DAY;

-- Copies each insert into frames_raw on to frames, so Spate writes one table.
CREATE MATERIALIZED VIEW IF NOT EXISTS frames_mv TO frames
AS SELECT * FROM frames_raw;
