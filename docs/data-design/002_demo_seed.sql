-- Deterministic demo catalog seed. Execute once after 001_initial.sql.
-- For repeated demos, reset database or use ON CONFLICT as below.
BEGIN;
INSERT INTO hotel.hotels(id,name,city,address,latitude,longitude,description)
VALUES
('10000000-0000-4000-8000-000000000001','HotelGenie Hà Nội Demo','Hà Nội','Hoàn Kiếm, Hà Nội, Việt Nam',21.028511,105.804817,'Dữ liệu minh họa, không phải khách sạn thật'),
('10000000-0000-4000-8000-000000000002','HotelGenie Đà Nẵng Demo','Đà Nẵng','Hải Châu, Đà Nẵng, Việt Nam',16.054407,108.202167,'Dữ liệu minh họa, không phải khách sạn thật')
ON CONFLICT (id) DO NOTHING;
INSERT INTO hotel.rooms(id,hotel_id,name,capacity,price_per_night_vnd)
VALUES
('20000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000001','Standard Twin',2,900000),
('20000000-0000-4000-8000-000000000002','10000000-0000-4000-8000-000000000001','Family',4,1500000),
('20000000-0000-4000-8000-000000000003','10000000-0000-4000-8000-000000000002','City View',2,1100000)
ON CONFLICT (id) DO NOTHING;
COMMIT;
