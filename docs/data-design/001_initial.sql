-- HotelGenie Data Design v1.0 - PostgreSQL 15+ baseline, proposed ADRs
-- Execute with database OWNER/migration identity; separate per-service DB users in deployment.
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS btree_gist;
CREATE SCHEMA IF NOT EXISTS auth;
CREATE SCHEMA IF NOT EXISTS hotel;
CREATE SCHEMA IF NOT EXISTS booking;
CREATE SCHEMA IF NOT EXISTS review;

CREATE TABLE auth.users (
 id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
 email VARCHAR(255) NOT NULL,
 full_name VARCHAR(120) NOT NULL,
 password_hash TEXT NOT NULL,
 role VARCHAR(24) NOT NULL DEFAULT 'customer' CHECK (role IN ('customer','admin')),
 active BOOLEAN NOT NULL DEFAULT TRUE,
 created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
 updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
 CONSTRAINT users_email_trim CHECK (email = btrim(email) AND char_length(email) > 3)
);
CREATE UNIQUE INDEX uq_auth_users_email_ci ON auth.users (lower(email));

CREATE TABLE hotel.hotels (
 id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
 name VARCHAR(180) NOT NULL,
 city VARCHAR(120) NOT NULL,
 address TEXT NOT NULL,
 latitude NUMERIC(9,6) NOT NULL CHECK (latitude BETWEEN -90 AND 90),
 longitude NUMERIC(9,6) NOT NULL CHECK (longitude BETWEEN -180 AND 180),
 description TEXT,
 active BOOLEAN NOT NULL DEFAULT TRUE,
 created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
 updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX ix_hotels_city ON hotel.hotels (lower(city)) WHERE active;
CREATE TABLE hotel.rooms (
 id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
 hotel_id UUID NOT NULL REFERENCES hotel.hotels(id) ON DELETE RESTRICT,
 name VARCHAR(160) NOT NULL,
 capacity SMALLINT NOT NULL CHECK (capacity BETWEEN 1 AND 20),
 price_per_night_vnd BIGINT NOT NULL CHECK (price_per_night_vnd >= 0),
 active BOOLEAN NOT NULL DEFAULT TRUE,
 created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
 updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX ix_rooms_hotel_active_price ON hotel.rooms(hotel_id, price_per_night_vnd, id) WHERE active;

-- Cross-service IDs (room_id/user_id) have NO foreign keys by design.
CREATE TABLE booking.bookings (
 id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
 user_id UUID NOT NULL,
 room_id UUID NOT NULL,
 check_in DATE NOT NULL,
 check_out DATE NOT NULL,
 guests SMALLINT NOT NULL CHECK (guests BETWEEN 1 AND 20),
 price_per_night_vnd BIGINT NOT NULL CHECK (price_per_night_vnd >= 0),
 total_price_vnd BIGINT NOT NULL CHECK (total_price_vnd >= 0),
 status VARCHAR(24) NOT NULL DEFAULT 'confirmed' CHECK (status IN ('confirmed','cancelled')),
 created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
 cancelled_at TIMESTAMPTZ,
 CONSTRAINT valid_booking_dates CHECK (check_out > check_in),
 CONSTRAINT valid_cancel_timestamp CHECK ((status = 'confirmed' AND cancelled_at IS NULL) OR (status = 'cancelled' AND cancelled_at IS NOT NULL)),
 CONSTRAINT booking_total_math CHECK (total_price_vnd = (check_out - check_in)::BIGINT * price_per_night_vnd),
 CONSTRAINT no_overlapping_confirmed_booking EXCLUDE USING gist
  (room_id WITH =, daterange(check_in, check_out, '[)') WITH &&)
  WHERE (status = 'confirmed')
);
CREATE INDEX ix_bookings_user_created ON booking.bookings(user_id, created_at DESC, id DESC);
CREATE INDEX ix_bookings_room_dates ON booking.bookings(room_id, check_in, check_out);

-- Unique per user+route+key: request_hash prevents same key reused with different payload.
CREATE TABLE booking.idempotency_keys (
 user_id UUID NOT NULL,
 route VARCHAR(120) NOT NULL,
 idempotency_key VARCHAR(128) NOT NULL,
 request_hash CHAR(64) NOT NULL,
 booking_id UUID REFERENCES booking.bookings(id) ON DELETE RESTRICT,
 response_status SMALLINT,
 created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
 PRIMARY KEY(user_id, route, idempotency_key),
 CONSTRAINT idem_response_status CHECK (response_status IS NULL OR response_status BETWEEN 200 AND 599)
);
CREATE TABLE booking.outbox (
 id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
 event_type VARCHAR(100) NOT NULL CHECK (event_type IN ('booking.created','booking.cancelled')),
 event_version INT NOT NULL DEFAULT 1 CHECK (event_version >= 1),
 aggregate_id UUID NOT NULL,
 correlation_id UUID NOT NULL,
 payload JSONB NOT NULL,
 created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
 published_at TIMESTAMPTZ,
 attempts INT NOT NULL DEFAULT 0 CHECK (attempts >= 0),
 last_error TEXT
);
CREATE INDEX ix_booking_outbox_unpublished ON booking.outbox(created_at,id) WHERE published_at IS NULL;

CREATE TABLE review.reviews (
 id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
 user_id UUID NOT NULL,
 hotel_id UUID NOT NULL,
 rating SMALLINT NOT NULL CHECK (rating BETWEEN 1 AND 5),
 content TEXT NOT NULL CHECK (char_length(btrim(content)) BETWEEN 1 AND 5000),
 submission_version INT NOT NULL DEFAULT 1 CHECK (submission_version >= 1),
 moderation_status VARCHAR(24) NOT NULL DEFAULT 'pending' CHECK (moderation_status IN ('pending','approved','flagged','rejected')),
 sentiment VARCHAR(12) CHECK (sentiment IN ('positive','neutral','negative')),
 moderation_reason TEXT,
 created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
 moderated_at TIMESTAMPTZ,
 CONSTRAINT moderation_consistency CHECK (
   (moderation_status = 'pending' AND moderated_at IS NULL)
   OR (moderation_status <> 'pending' AND moderated_at IS NOT NULL)
 )
);
CREATE INDEX ix_reviews_hotel_public ON review.reviews(hotel_id, created_at DESC,id DESC) WHERE moderation_status = 'approved';
CREATE INDEX ix_reviews_pending ON review.reviews(created_at,id) WHERE moderation_status = 'pending';
CREATE TABLE review.outbox (
 id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
 event_type VARCHAR(100) NOT NULL CHECK (event_type='review.submitted'),
 event_version INT NOT NULL DEFAULT 1 CHECK (event_version>=1),
 aggregate_id UUID NOT NULL REFERENCES review.reviews(id) ON DELETE RESTRICT,
 correlation_id UUID NOT NULL,
 payload JSONB NOT NULL,
 created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
 published_at TIMESTAMPTZ,
 attempts INT NOT NULL DEFAULT 0 CHECK (attempts >= 0),
 last_error TEXT
);
CREATE INDEX ix_review_outbox_unpublished ON review.outbox(created_at,id) WHERE published_at IS NULL;
CREATE TABLE review.processed_events (
 consumer_name VARCHAR(100) NOT NULL,
 event_id UUID NOT NULL,
 processed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
 PRIMARY KEY(consumer_name,event_id)
);

-- An AI moderation producer can use review.moderated event persisted in ai-owned schema.
CREATE SCHEMA IF NOT EXISTS ai;
CREATE TABLE ai.outbox (
 id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
 event_type VARCHAR(100) NOT NULL CHECK(event_type='review.moderated'),
 event_version INT NOT NULL DEFAULT 1 CHECK(event_version>=1),
 aggregate_id UUID NOT NULL,
 correlation_id UUID NOT NULL,
 payload JSONB NOT NULL,
 created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
 published_at TIMESTAMPTZ,
 attempts INT NOT NULL DEFAULT 0 CHECK (attempts>=0),
 last_error TEXT
);
CREATE INDEX ix_ai_outbox_unpublished ON ai.outbox(created_at,id) WHERE published_at IS NULL;
CREATE TABLE ai.processed_events (
 consumer_name VARCHAR(100) NOT NULL,
 event_id UUID NOT NULL,
 processed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
 PRIMARY KEY (consumer_name,event_id)
);
COMMIT;
