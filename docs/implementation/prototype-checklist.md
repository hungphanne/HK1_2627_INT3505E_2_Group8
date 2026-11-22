# Prototype gates – checked only after actually demonstrated

## Before coding
- [ ] Review open decisions D-01, D-04, D-05
- [ ] Import issues from tasks.csv and assign DRI/reviewers
- [ ] Commit latest 01–07 docs + contract/event/migration files
- [ ] CI validates YAML/event JSON schemas and examples

## Prototype evidence
- [ ] Compose boot on clean machine
- [ ] DB migration/seed verified
- [ ] JWT/auth 401 and ownership test
- [ ] Search seeded rooms via Gateway
- [ ] Booking create/get/cancel with price snapshot
- [ ] 2 concurrent overlapping booking requests -> <=1 confirmed
- [ ] Same idempotency key+payload replays one booking/event
- [ ] Outbox relay to Redis -> audit consumer (event ID logged)
- [ ] Newman/pytest outputs archived
- [ ] docs/08 includes exact reproduction steps
