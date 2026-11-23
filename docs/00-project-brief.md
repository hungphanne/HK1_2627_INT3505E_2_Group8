# HotelGenie — Project Brief

**Nhóm 8 · INT3505E 2 · Tuần 12 (Design Review)** · Chi tiết đầy đủ trong tài liệu 01–07.

## 1. Bài toán và giá trị

Đặt phòng khách sạn hiện nay buộc khách tự làm ba việc rời rạc: chỉnh nhiều bộ lọc để tìm phòng, đọc nhiều review không được kiểm duyệt để đánh giá khách sạn, rồi tự tra cứu cách đi lại và chỗ ăn chơi quanh nơi ở.

HotelGenie gộp ba việc đó vào một hệ thống theo kiến trúc hướng dịch vụ:

- Tìm phòng bằng một câu tiếng Việt. AI chỉ trích xuất bộ lọc; phòng, giá và tình trạng trống luôn lấy từ dữ liệu thật của Hotel Service và Booking Service.
- Review được AI phân tích cảm xúc và kiểm duyệt trước khi công khai, xử lý bất đồng bộ qua Redis Streams.
- Gợi ý đi lại, ăn uống, giải trí gần khách sạn, chỉ từ dữ liệu địa điểm có thật, kèm lời giải thích.

## 2. API consumers

| Consumer | Dùng API để |
| --- | --- |
| React frontend (khách hàng) | Đăng ký, đăng nhập, tìm phòng (bộ lọc và prompt), đặt và huỷ phòng, gửi và xem review, xem gợi ý gần khách sạn |
| Các service nội bộ | Booking gọi Hotel lấy thông tin phòng; Hotel gọi Booking kiểm tra phòng trống (`openapi-internal.yaml`) |
| Consumer bất đồng bộ | AI worker nhận `review.submitted`; Review Service nhận `review.moderated`; consumer audit nhận `booking.created` và `booking.cancelled` |

## 3. Use cases chính

| Mã | Use case | API |
| --- | --- | --- |
| UC-AUTH | Đăng ký, đăng nhập nhận JWT | `POST /auth/register`, `POST /auth/token` |
| UC-05 | Đặt phòng an toàn, không đặt trùng | `POST /bookings` (Idempotency-Key) |
| UC-08 | Tìm phòng bằng ngôn ngữ tự nhiên | `POST /ai/searches` |
| UC-09 | Gửi review và kiểm duyệt bằng AI | `POST /reviews` → `review.submitted` → `review.moderated` |
| UC-10 | Gợi ý địa điểm gần khách sạn | `GET /hotels/{hotel_id}/nearby-places` |

**Luồng nghiệp vụ trọng tâm (demo tuần 12–15):** tìm phòng bằng prompt → đăng nhập → đặt phòng → xem gợi ý gần khách sạn → gửi review và theo dõi kiểm duyệt.

## 4. Phạm vi MVP

| Thuộc MVP (P0) | Ngoài phạm vi |
| --- | --- |
| 5 service Flask (Auth, Hotel, Booking, Review, AI) + API Gateway | Thanh toán, hoàn tiền thật |
| JWT, chỉ xem và huỷ booking của chính mình | Ứng dụng mobile native |
| Danh mục khách sạn, phòng; lọc theo thành phố, ngày, số khách, giá; phân trang | Tự huấn luyện hoặc fine-tune mô hình AI |
| Đặt, xem, huỷ booking; chống đặt trùng bằng ràng buộc DB | Bản đồ trực tiếp, đặt xe theo thời gian thực |
| Review chờ kiểm duyệt; AI phân tích cảm xúc và kiểm duyệt qua Redis Streams | Giá động, khách hàng thân thiết, đa tiền tệ |
| AI tìm phòng bằng prompt, AI gợi ý địa điểm có dữ liệu dự phòng | Trang quản trị (P1, nếu còn thời gian) |
| Docker Compose chạy được bằng một lệnh | |

## 5. Công nghệ

Python + Flask, PostgreSQL + SQLAlchemy, Redis Streams, Gemini API qua lớp adapter, JWT, React + Vite, Docker Compose, OpenAPI 3.0.3 + Swagger UI, Pytest + Postman/Newman.

## 6. Rủi ro chính

| Rủi ro | Cách xử lý |
| --- | --- |
| Phạm vi lớn (5 service + event) trong 4 tuần, nhóm chưa làm AI | Ưu tiên luồng Auth → Hotel → Booking; AI dùng fake adapter trước, Gemini sau |
| Gemini hết quota hoặc lỗi | Provider interface, fake adapter, dữ liệu địa điểm dự phòng |
| Đặt trùng khi có request đồng thời | Exclusion constraint PostgreSQL + transaction |
| Event bị giao lặp | Consumer idempotent, dedupe theo `event_id` |
