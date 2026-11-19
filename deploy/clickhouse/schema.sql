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
-- seven days outlives any drill report. Rows expire seven days after they're
-- delivered, not after the gateway saw them, so a replay of old frames from
-- Redpanda stays long enough to be counted.
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
TTL toDateTime(inserted_at) + INTERVAL 7 DAY;

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

-- One row per second for each boot, system and message: how many frames
-- arrived and how long the first copy took from the gateway to ClickHouse.
-- Each refresh writes the second again, so the latest refresh wins.
CREATE TABLE IF NOT EXISTS frames_per_second
(
    boot_id      UUID,
    system_id    UInt8,
    msg_id       UInt32,
    second       DateTime('UTC'),
    frames       UInt64,
    latency_p50  Float64,
    latency_p99  Float64,
    refreshed_at DateTime64(6, 'UTC')
)
ENGINE = ReplacingMergeTree(refreshed_at)
ORDER BY (boot_id, system_id, msg_id, second)
TTL second + INTERVAL 90 DAY;

-- A plain materialised view runs on each insert, before any merge, so it
-- would count a redelivered batch twice. This one runs every 10 seconds
-- instead. It finds the seconds that gained a row since its last refresh,
-- however old they are, and recounts them from frames_raw, grouping by
-- offset so each frame counts once at its first arrival. The watermark is
-- the rollup's own latest refreshed_at, so a refresh that was missed, or a
-- server that was down, is caught up on the next run.
CREATE MATERIALIZED VIEW IF NOT EXISTS frames_per_second_mv
REFRESH EVERY 10 SECOND APPEND TO frames_per_second
AS
WITH touched AS
(
    SELECT DISTINCT boot_id, system_id, toStartOfSecond(received_at) AS second
    FROM frames_raw
    -- A minute's overlap catches rows that landed while the last refresh
    -- ran. An empty rollup counts everything once.
    WHERE inserted_at >= (SELECT max(refreshed_at) FROM frames_per_second) - INTERVAL 1 MINUTE
)
SELECT
    boot_id,
    system_id,
    msg_id,
    toDateTime(second) AS second,
    count() AS frames,
    quantileExact(0.5)(latency_ms) AS latency_p50,
    quantileExact(0.99)(latency_ms) AS latency_p99,
    now64(6) AS refreshed_at
FROM
(
    SELECT
        boot_id,
        system_id,
        any(msg_id) AS msg_id,
        toStartOfSecond(any(received_at)) AS second,
        dateDiff('millisecond', any(received_at), min(inserted_at)) AS latency_ms
    FROM frames_raw
    WHERE (boot_id, system_id, toStartOfSecond(received_at)) IN (SELECT * FROM touched)
      AND received_at >= (SELECT min(second) FROM touched)
    GROUP BY boot_id, system_id, partition, offset
)
GROUP BY boot_id, system_id, msg_id, second;
