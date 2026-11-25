# HotelGenie — 08. Development & Testing (bản tuần 12)

**Mã:** HG-DEV-08 · **Phiên bản:** v0.1 (tuần 12 – Design Review) · **Ngày:** 23/11/2026
**Phạm vi:** Tuần 12 chỉ có hợp đồng thiết kế, chưa có backend. Tài liệu này hướng dẫn xem OpenAPI, chạy mock server và kịch bản demo. Phần chạy Docker Compose, kiểm thử và Newman sẽ bổ sung từ tuần 13 theo IMP-02 và IMP-15.

## 1. Yêu cầu công cụ

| Công cụ | Dùng để | Kiểm tra |
| --- | --- | --- |
| Python 3.10+ | Chạy web server tĩnh cho Swagger UI, `validate_contracts.py` | `python --version` |
| Node.js 18+ | Chạy Prism mock server qua `npx` | `node --version` |
| Trình duyệt | Swagger UI | — |

## 2. Xem hợp đồng API bằng Swagger UI

```bash
cd docs/contracts
python -m http.server 8000
```

Mở `http://localhost:8000/swagger.html`. Góc trên bên phải có ô chọn giữa **Public API** và **Internal API**. Không mở `swagger.html` bằng cách bấm đúp file: trình duyệt sẽ chặn đọc file YAML.

## 3. Chạy mock server (không cần database)

```bash
cd docs/contracts
npx @stoplight/prism-cli mock openapi-public.yaml
```

Mock chạy tại `http://127.0.0.1:4010`. Trong Swagger UI chọn server **Prism mock server** để nút *Try it out* gọi vào mock. Prism trả `example` khai báo trong OpenAPI; thêm header `Prefer: code=409` hoặc `Prefer: example=<tên>` để lấy một response cụ thể.

Prism tự kiểm tra request theo contract: thiếu header bắt buộc (ví dụ `Idempotency-Key`) hoặc sai kiểu dữ liệu sẽ bị trả lỗi, và các route cần JWT trả `401` nếu không có header `Authorization`.

## 4. Kịch bản demo tuần 12 (góc nhìn API consumer)

Dữ liệu dùng theo `docs/data-design/002_demo_seed.sql`: khách sạn Đà Nẵng `10000000-0000-4000-8000-000000000002`, phòng `20000000-0000-4000-8000-000000000003`.

| Bước | Operation | Điểm cần trình bày |
| --- | --- | --- |
| 1 | `POST /api/v1/ai/searches` | AI chỉ trích xuất `filters`; phòng lấy từ Hotel Service. Ví dụ thiếu ngày → `needs_clarification=true` |
| 2 | `POST /api/v1/auth/token` | Nhận JWT để gọi các route riêng tư |
| 3 | `POST /api/v1/bookings` | `Idempotency-Key`, `201` + `Location`; cùng phòng và ngày → `409 BOOKING_OVERLAP` |
| 4 | `GET /api/v1/hotels/{hotel_id}/nearby-places` | `source`, `is_fallback`, lời giải thích chỉ dựa trên địa điểm có thật trong dữ liệu |
| 5 | `POST /api/v1/reviews` | Review ở trạng thái `pending`; AI xử lý bất đồng bộ qua Redis Streams |

```bash
BASE=http://127.0.0.1:4010/api/v1

# 1. Tìm phòng bằng câu tiếng Việt
curl -s -X POST $BASE/ai/searches -H "Content-Type: application/json" \
  -d '{"prompt":"Phòng ở Đà Nẵng cho 2 người từ 19/12 đến 21/12, dưới 1,2 triệu"}'

# 2. Đăng nhập
curl -s -X POST $BASE/auth/token -H "Content-Type: application/json" \
  -d '{"email":"an@example.com","password":"matkhau123"}'

# 3. Đặt phòng (mock chấp nhận token bất kỳ)
curl -si -X POST $BASE/bookings \
  -H "Authorization: Bearer demo" -H "Idempotency-Key: demo-key-0001" \
  -H "Content-Type: application/json" \
  -d '{"room_id":"20000000-0000-4000-8000-000000000003","check_in":"2026-12-19","check_out":"2026-12-21","guests":2}'

# 4. Gợi ý ăn uống gần khách sạn
curl -s "$BASE/hotels/10000000-0000-4000-8000-000000000002/nearby-places?category=food&radius_m=2000"

# 5. Gửi review
curl -s -X POST $BASE/reviews -H "Authorization: Bearer demo" -H "Content-Type: application/json" \
  -d '{"hotel_id":"10000000-0000-4000-8000-000000000002","rating":4,"content":"Phòng sạch, gần cầu Rồng."}'
```

### Các trường hợp lỗi

```bash
# 401 – thiếu token
curl -si $BASE/bookings

# 409 – phòng đã có booking trùng ngày
curl -si -X POST $BASE/bookings -H "Prefer: code=409" \
  -H "Authorization: Bearer demo" -H "Idempotency-Key: demo-key-0002" \
  -H "Content-Type: application/json" \
  -d '{"room_id":"20000000-0000-4000-8000-000000000003","check_in":"2026-12-19","check_out":"2026-12-21","guests":2}'

# 503 – AI provider lỗi
curl -si -X POST $BASE/ai/searches -H "Prefer: code=503" \
  -H "Content-Type: application/json" -d '{"prompt":"phòng Đà Nẵng"}'
```

Mọi lỗi đều trả `application/problem+json` theo schema `Problem` (`type`, `title`, `status`, `detail`, `code`, `request_id`).

## 5. Kiểm tra tĩnh hợp đồng

```bash
pip install pyyaml jsonschema
python docs/contracts/validate_contracts.py
```

Trước khi nộp, dán `openapi-public.yaml` vào https://editor.swagger.io để chắc chắn không có lỗi cú pháp.

## 6. Trạng thái kiểm thử

| Hạng mục | Trạng thái tuần 12 |
| --- | --- |
| OpenAPI mở được trên Swagger UI, có example | Có |
| Prism mock chạy được luồng demo | Có |
| Event schema + example (`validate_contracts.py`) | Có |
| Contract test với Flask, pytest, Newman | Chưa – tuần 13–15 (IMP-15) |
| Docker Compose chạy đủ service | Chưa – tuần 13 (IMP-02) |
