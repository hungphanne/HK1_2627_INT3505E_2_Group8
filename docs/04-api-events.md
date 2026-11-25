# HotelGenie — 04. API & Event Contracts

**Mã:** HG-CONTRACT-04 · **Phiên bản:** v1.0 DRAFT · **Ngày:** 19/11/2026  
**Nguồn đối chiếu:** Charter v1.0, SRS v1.0, SAD v1.0, SOA B1–B9.\
**Lưu ý:** Đây là hợp đồng thiết kế **chưa có implementation hoặc test E2E**; các lựa chọn ở SAD được đánh dấu đề xuất không tự động trở thành quyết định đã duyệt.

## 1. Mục tiêu và cấu trúc deliverable

- `contracts/openapi-public.yaml`: 15 HTTP operations công khai trên 13 paths, OpenAPI **3.0.3**, có tag, operationId, request/response schema, HTTP status, JWT bearer.
- `contracts/openapi-internal.yaml`: 2 service-to-service operations, **không public**.
- `contracts/events/*.schema.json`: 4 JSON Schemas Draft 2020-12 cho Redis Streams event envelope và payload.
- `contracts/examples/`: payload minh họa giả định (không phải dữ liệu thực tế).
- `contracts/validate_contracts.py`: kiểm tra cấu trúc tĩnh và examples, **không phải** contract test chạy trên server.

Quy ước SOA: mỗi service sở hữu một năng lực nghiệp vụ; client dùng contract thay vì truy cập DB hoặc biết ORM model. B1/B5. Hợp đồng là boundary giữa nhóm phát triển song song.

## 2. Những quy tắc HTTP được áp dụng

- Public base path `/api/v1`; `application/json` cho kết quả thông thường, `application/problem+json` cho lỗi theo Problem Details RFC 9457 (slide B3 nhắc RFC 7807/9457).
- Dùng tài nguyên danh từ số nhiều: hotels, rooms, bookings, reviews; POST auth token và AI searches là **workflow resource**; không dùng `GET /createBooking`.
- GET chỉ đọc, POST tạo mới (201 + Location khi trả resource), PATCH hủy booking bằng trạng thái được khai báo. JWT bearer cho route riêng tư.
- `400` malformed input / query; `401` thiếu hoặc token sai; `404` không thấy tài nguyên hoặc che giấu resource khác owner; `409` booking overlap, same idempotency key khác payload; `422` semantic validation; `503` dependency unavailable. Phải thống nhất mapper lỗi khi implement.
- Error response (schema `Problem`) gồm `type`, `title`, `status`, `detail`, `code`, `request_id` và `instance` tùy chọn. Public API có thể trả `errors` trong lỗi validation 400/422, với `field` và `message` cho từng mục. Không đưa dữ liệu nhạy cảm vào thông báo.
- Hotels/Rooms dùng phân trang offset với `page=1` và `per_page=20` mặc định, tối đa 100 phần tử mỗi trang. `GET /api/v1/hotels` nhận `sort` theo whitelist `name`, `-name`, `city`, `-city` (mặc định `name`); dùng ID để phân định đồng hạng. Với các danh sách khác, default/max và whitelist vẫn là đề xuất trước khi freeze.
- `check_in`, `check_out` ở dạng `YYYY-MM-DD`, khoảng `[check_in, check_out)`; `check_out > check_in`. Timestamp sự kiện UTC ISO 8601.
- ID là UUID string; tiền là **số nguyên VND**; không dùng floating-point để tính giá.

## 3. Public API inventory và owner

| Owner | Method | Route | Xác thực | FR/UC chính |
|---|---|---|---|---|
| Auth | POST | `/api/v1/auth/register` | Không | FR-AUTH-01 |
| Auth | POST | `/api/v1/auth/token` | Không | FR-AUTH-02 |
| Auth | GET | `/api/v1/users/me` | JWT | FR-AUTH-03 |
| Hotel | GET | `/api/v1/hotels` | Không | FR-HOTEL-01/03/04 |
| Hotel | GET | `/api/v1/hotels/{hotel_id}` | Không | FR-HOTEL-02 |
| Hotel | GET | `/api/v1/hotels/{hotel_id}/rooms` | Không | FR-HOTEL-02/05 |
| Hotel | GET | `/api/v1/rooms/{room_id}` | Không | FR-HOTEL-05 |
| Booking | POST | `/api/v1/bookings` | JWT, `Idempotency-Key` | FR-BOOK-01/02/05 |
| Booking | GET | `/api/v1/bookings` | JWT | FR-BOOK-03 |
| Booking | GET | `/api/v1/bookings/{booking_id}` | JWT | FR-BOOK-03 |
| Booking | PATCH | `/api/v1/bookings/{booking_id}` | JWT | FR-BOOK-04/05 |
| Review | POST | `/api/v1/reviews` | JWT | FR-REV-01/02 |
| Review | GET | `/api/v1/hotels/{hotel_id}/reviews` | Không | FR-REV-05 |
| AI | POST | `/api/v1/ai/searches` | Không | FR-AI-01..04 |
| AI | GET | `/api/v1/hotels/{hotel_id}/nearby-places` | Không | FR-PLACE-01..05 |

**Lưu ý route Gateway:** Dù cùng prefix `/hotels/{hotel_id}`, endpoint `/reviews` phải route tới Review Service và `/nearby-places` tới AI Service; không để rule `/hotels/` tổng quát bắt hết.

## 4. Hợp đồng tìm phòng và tính khả dụng

1. Client GET hotels hoặc hotel rooms kèm bộ lọc ngày/số khách/giá; frontend không tự phán đoán khả dụng.
2. Hotel Service lấy catalog và giá, gọi **Booking internal availability batch** nếu yêu cầu lọc theo ngày. Không được chỉ dựa vào cột `room.active`.
3. Booking availability đọc dữ liệu booking thuộc schema của mình và trả ID phòng chưa bị chiếm theo `[check_in, check_out)`; API này là **read-only check**, không giữ chỗ.
4. Hotel Service phối hợp room availability, trả kết quả theo thứ tự ổn định và metadata phân trang khớp tập đã lọc. Cần quy định search pagination pipeline tránh lọc sau khi cắt trang rồi tạo trang thiếu phòng. Đề xuất cho MVP seed nhỏ: lọc catalog, batch availability toàn bộ ứng viên trong giới hạn, rồi mới paginate.
5. Booking Service khi nhận POST booking gọi Hotel internal snapshot để xác thực `room.active`, `capacity`, giá, sau đó insert với **DB transaction + exclusion constraint** (SAD ADR-02), không dựa vào kết quả bước 3. Nếu hai POST cùng lúc trùng phòng/đêm, tối đa một request tạo được booking.
6. Không có vòng gọi lồng nhau: GET search chạy Hotel→Booking availability (chỉ DB Booking); POST booking chạy Booking→Hotel snapshot (chỉ DB Hotel).

**Hai internal operations:** `GET /internal/v1/rooms/{room_id}/booking-snapshot` (Hotel); `POST /internal/v1/availability/check` (Booking). Mỗi service phải chặn truy cập từ browser/public Gateway và có credential nội bộ. YAML hiện khai báo bearerAuth **placeholder**; chưa quyết định service JWT hay phương án khác (SAD ADR-06).

## 5. Booking: idempotency và lỗi

### 5.1. Tạo booking

Request minh họa trong `examples/booking-request.json`:

```json
{
  "room_id": "11111111-1111-4111-8111-111111111111",
  "check_in": "2026-12-01",
  "check_out": "2026-12-03",
  "guests": 2
}
```

Client gửi `Authorization: Bearer <token>` và `Idempotency-Key: <opaque-unique-key>`. `user_id` **không nhận từ body**, lấy từ JWT claim sau verify. Kết quả tạo lần đầu `201` + `Location: /api/v1/bookings/{booking_id}`, cùng body `Booking`. Cùng owner + key + body trả replay `201` + **cùng response và Location** (`Idempotent-Replayed: true`); key trùng nhưng payload khác trả `409` với `code=IDEMPOTENCY_KEY_REUSED`. Header `Idempotent-Replayed` false/lược bỏ cho lần tạo mới.

**Business conflicts:** `BOOKING_OVERLAP` → 409; `ROOM_INACTIVE` hoặc guests vượt capacity → 422; snapshot service timeout → 503/504 (v1 YAML hiện liệt kê 503). `Idempotency-Key` thiếu: cần thống nhất 400 ở implementation. Dự kiến idempotency lưu cùng booking/outbox trong DB transaction; response replay không tạo event lần 2.

### 5.2. Hủy booking

`PATCH /api/v1/bookings/{booking_id}` body `{"status":"cancelled"}`. Trả `200` với Booking đã hủy. Gửi lại PATCH sau khi đã hủy: vẫn 200, body thể hiện trạng thái cancelled, **không phát `booking.cancelled` lần 2**. Access control: chỉ owner được phép; để tránh lộ resource, đề xuất 404 cho resource người khác. Quy tắc không cho hủy sau check-in **chưa chốt**, vì SRS DEC-04 vẫn mở. Nếu quy tắc được duyệt, cập nhật 409 và test tương ứng.

## 6. Review và xử lý AI bất đồng bộ

- `POST /api/v1/reviews`: JWT, `hotel_id`, `rating` 1–5, `content`; ghi review `pending`, trả 201. Review không được công khai ngay.
- Ghi `review.submitted` vào outbox cùng transaction, relay publish lên Redis Stream; AI worker nhận, validate schema, xử lý Gemini, lưu kết quả bền vững, phát `review.moderated`; Review consumer update trạng thái.
- `GET /api/v1/hotels/{hotel_id}/reviews` chỉ trả `approved`.
- AI thất bại giữ trạng thái pending và retry; **không tự duyệt**.
- Khi replay, AI phải dùng idempotency key bền vững dựa trên `review_id + submission_version` hoặc `submission_event_id`; receiver dedupe `event_id` và kiểm tra `submission_version` trước khi update.
- **Mở:** điều kiện người được review (chỉ đã lưu trú hay mọi user), giới hạn một review; chốt trong SRS trước khi production-like implementation.

## 7. Redis Streams event contracts

### 7.1. Envelope

Các schema JSON trong thư mục `events/` yêu cầu: `event_id` (UUID), `event_type`, `event_version` (1), `occurred_at` (UTC), `correlation_id`, `producer`, `payload`. Producer không publish password, JWT, API key. **Redis Stream entry ID** do Redis cấp **khác** `event_id` dùng dedupe nghiệp vụ.

| `event_type` | Producer | Consumer dự kiến | Hệ quả |
|---|---|---|---|
| `booking.created` | Booking | Demo/audit consumer hoặc consumer được xác định sau | Theo dõi đặt phòng |
| `booking.cancelled` | Booking | Demo/audit consumer hoặc consumer được xác định sau | Theo dõi hủy |
| `review.submitted` | Review | AI moderation worker | Kiểm duyệt review |
| `review.moderated` | AI | Review worker | Cập nhật trạng thái review |

**Đề xuất stream names:** `hotelgenie:events:booking` và `hotelgenie:events:review`. Hai loại review event trên cùng stream cần **consumer group và filter được thiết kế cẩn thận**: consumer group *phân chia* message, không broadcast; một group AI đọc trọn stream và bỏ qua không hợp lệ có thể làm mất event cần xử lý ở group khác nếu chia group sai. **Khuyến nghị cho MVP:** tách `hotelgenie:events:review-submitted` và `hotelgenie:events:review-moderated`, mỗi stream một nhóm consumer tương ứng; vẫn cần chốt tại ADR-03. Booking có thể ở stream riêng. Như vậy giảm nhầm lẫn routing và ACK.

### 7.2. Publish / ACK / lỗi

1. Writer ghi domain record, outbox row cùng PostgreSQL transaction; nếu commit thất bại, **không publish**.
2. Relay đọc pending outbox, gọi `XADD`; chỉ đánh dấu published sau thành công. Crash giữa `XADD` và đánh dấu gây duplicate là bình thường (at-least-once).
3. Consumer `XREADGROUP`, xác thực `event_version`/schema, dedupe trong PostgreSQL rồi update business state **cùng transaction**.
4. Chỉ `XACK` sau DB commit thành công (hoặc durable result/outbox của AI đã lưu). Với pending event khi crash, reclaim bằng `XAUTOCLAIM`.
5. Retry có giới hạn, backoff và dead-letter stream có `event_id`, loại, lý do lỗi tối thiểu; **chưa chốt retry count/timeouts và retention**.

**Không hứa exactly-once delivery.** Điều mong muốn là at-least-once transport + idempotent business effect.

### 7.3. Cần xử lý kỹ ở AI consumer

`review.submitted` mang `content` để moderation; đây là dữ liệu người dùng. Không log raw content mặc định. `review.moderated` phải có `submission_event_id` và `submission_version` để tránh kết quả cũ ghi đè review mới. Các schema cho phép tạo event trong bài lab, nhưng **không có policy độc lập về nội dung review** cho tới khi 06-AI Spec được chốt.

## 8. AI search và Nearby

**AI Search:** POST `/api/v1/ai/searches` nhận `prompt`; AI trả `filters` có trường nullable, `needs_clarification`, `clarification_fields` và `rooms` từ dữ liệu thực Hotel/Booking. Nếu thiếu `check_in`/`check_out` cần để xác định khả dụng, **không được trình bày phòng là “available”**. Response ở v1 chưa có field `availability_verified`, nên trước khi freeze contract nên thêm trường minh bạch cho trường hợp kết quả tham khảo và có check theo ngày.

**Nearby:** GET `/api/v1/hotels/{hotel_id}/nearby-places` hỗ trợ `category`, `radius_m` (đề xuất). Places adapter trả `source=google|osm|seed`, `is_fallback`, tọa độ và giải thích; AI không bịa địa điểm. **Provider live chưa chốt**; enum có cả google/osm cho khả năng thay thế. Seed fallback khi live provider lỗi phải được gắn nhãn.

## 9. JWT, internal security, versioning

- JWT: access token trong `Authorization` bearer, verify `exp`, `iss`, `aud`, `sub`, chữ ký. `401` cho thiếu/sai token; ownership ở từng service. **Thuật toán RS256 vs HS256 chưa phê duyệt** (SAD ADR-06), không gắn cứng trong OpenAPI.
- Internal routes ở network chỉ backend; service auth có secret hoặc machine credential tùy ADR. JWT người dùng không tự trao quyền gọi internal API.
- Public `/api/v1` là contract của client; thay đổi breaking phải có v2 riêng theo B9. Không xóa field, đổi kiểu dữ liệu hay đổi nghĩa status code trong v1 một cách im lặng.
- B9 minh chứng: thực hiện một endpoint v2 nhỏ riêng biệt + compatibility test cho client v1 khi dự án có code; chưa tính là đã thực hiện.

## 10. Test và mức độ sẵn sàng

| Check | Công cụ | Trạng thái |
|---|---|---|
| YAML có thể parse và tham chiếu schema nội bộ hợp lệ | Python/PyYAML, static checker | Có script kiểm tra |
| Event example hợp JSON Schema | `jsonschema` Draft202012 | Có script kiểm tra |
| OpenAPI spec semantic validation | `openapi-spec-validator`, Swagger Editor / Spectral | **Chưa chạy** nếu không có công cụ |
| Endpoint khớp Flask implementation | pytest/Connexion/contract tests | Chưa triển khai |
| Auth/Booking concurrency, event replay | pytest + Postgres/Redis | Chưa triển khai |
| Client E2E | Postman/Newman | Chưa triển khai |

## 11. Những quyết định phải chốt trước khi **freeze** hợp đồng

1. ADR-01: room vật lý, trạng thái booking `confirmed/cancelled`.
2. ADR-06: thuật toán JWT và cơ chế service credential.
3. SRS DEC-02/03: ai được review, review có gắn booking không.
4. SRS DEC-04: chính sách hủy sau check-in.
5. Redis event stream topology, consumer-group, retry/DLQ retention.
6. Phạm vi pagination/search: availability sau lọc, `page/per_page` defaults/max, `sort` whitelist.
7. `availability_verified` cho AI tìm phòng và semantic của bộ lọc thiếu ngày.
8. Internal port/URL thực tế; current YAML `service.internal` là **placeholder**.
9. OAuth2/refresh token không tự đưa vào MVP khi chưa chốt, dù B6 có giới thiệu.

## 12. Traceability tới slide và tài liệu nguồn

| Phần | Slide | Đã đưa vào hợp đồng |
|---|---|---|
| API as contract, client/server | B1 | service-owned public/internal interfaces |
| REST, methods, status, headers | B2 | GET/POST/PATCH, 200/201/4xx/5xx, bearer header |
| Resource naming, Problem Details, pagination | B3 | paths nhất quán, `Problem`, filters/page |
| OpenAPI paths/parameters/components/security | B4 | OAS 3.0.3 YAML, operationId, schemas |
| Resource ≠ DB model, hierarchy & pagination | B5 | Hotel/Room/Booking DTO, internal ownership |
| JWT, 401/403, role/ownership | B6 | bearer security, owner from JWT, no client user_id |
| Design-first / Flask service | B7 | contract để xây Flask blueprints, DTO/schema adapters |
| Schema/contract tests, pytest, Newman | B8 | validation script, testing requirements |
| Versioning / backward compatibility | B9 | `/api/v1`, planned v2 compatibility scenario |

**Không đánh đồng:** Redis Streams, Gemini, Places, PostgreSQL exclusion constraints, outbox và Nginx là lựa chọn của HotelGenie / SAD, **không phải bắt buộc từ B1–B9**.

## 13. Changelog

- **v1.0 DRAFT:** tách public/internal OpenAPI và Redis event schema; bổ sung ví dụ payload, nguyên tắc test; các điểm chưa chốt được ghi rõ.
