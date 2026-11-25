# HotelGenie — Tuyên bố dự án và Phạm vi (Project Charter & Scope)

**Phiên bản:** 1.0
**Ngày:** 19/11/2026  
**Quy mô nhóm:** 5 thành viên  
**Thời gian thực hiện:** 4 tuần  
**Mục đích:** Demo và báo cáo môn học Kiến trúc hướng dịch vụ  
**Trạng thái:** Đề xuất chốt công nghệ; phạm vi chi tiết và kiến trúc đang đề xuất.

## 1. Tổng quan dự án
HotelGenie là hệ thống đặt phòng khách sạn theo kiến trúc hướng dịch vụ (SOA): 
- Tích hợp AI để tìm phòng bằng ngôn ngữ tự nhiên
- phân tích/kiểm duyệt đánh giá và gợi ý phương tiện đi lại, ăn uống, giải trí gần khách sạn
- Các service giao tiếp đồng bộ qua REST API và bất đồng bộ qua Redis Streams.

## 2. Mục tiêu
1. Xây dựng và demo được quy trình hoàn chỉnh từ tìm phòng đến đặt phòng.
2. Thể hiện các service có ranh giới trách nhiệm rõ ràng, có thể triển khai độc lập và có hợp đồng REST/event cụ thể.
3. Demo ba trường hợp sử dụng AI với đầu vào, đầu ra có cấu trúc và kiểm chứng được.
4. Khởi chạy môi trường cục bộ bằng Docker Compose, có hướng dẫn demo và kiểm thử có thể tái lập.

## 3. Công nghệ đề xuất
| Thành phần | Công nghệ |
|---|---|
| Frontend | React + Vite |
| Backend | Python + Flask |
| Cơ sở dữ liệu / ORM | PostgreSQL + SQLAlchemy |
| Giao tiếp đồng bộ | REST API, đặc tả OpenAPI 3.0 |
| Giao tiếp bất đồng bộ | Redis Streams |
| AI | Gemini API qua lớp trừu tượng Provider Interface |
| Xác thực | JWT |
| Triển khai | Docker + Docker Compose |
| Kiểm thử | Pytest + Postman/Newman |
| Tài liệu | Markdown + OpenAPI; nội dung viết tiếng Việt |

## 4. Phạm vi MVP đề xuất (P0 — cần nhóm phê duyệt)
### 4.1. Chức năng khách hàng
- Đăng ký, đăng nhập, đăng xuất trên giao diện; cơ chế hết hạn/thu hồi JWT sẽ mô tả chi tiết sau.
- Xem danh sách khách sạn, phòng; lọc theo địa điểm, ngày lưu trú, số khách và mức giá.
- Xem chi tiết phòng, giá theo đêm và tình trạng khả dụng.
- Tạo booking; xem và hủy booking của chính mình.
- Gửi và xem đánh giá khách sạn theo trạng thái kiểm duyệt.

### 4.2. Chức năng AI
- **Tìm phòng bằng ngôn ngữ tự nhiên:** AI trích xuất bộ lọc từ prompt tiếng Việt; Hotel Service truy vấn phòng, giá và khả dụng thực tế. AI không được tự bịa phòng hoặc giá.
- **Phân tích và kiểm duyệt review:** AI xác định sắc thái đánh giá, đánh dấu spam/nội dung không phù hợp và đưa ra lý do. Review ở trạng thái chờ cho đến khi có kết quả kiểm duyệt; cần cơ chế dự phòng khi AI không hoạt động.
- **Gợi ý dịch vụ xung quanh:** AI chọn, xếp hạng và giải thích gợi ý đi lại, ăn uống, vui chơi từ bộ dữ liệu địa điểm mẫu có tọa độ đã kiểm chứng; không tự tạo địa điểm không có trong dữ liệu.

### 4.3. Minh chứng kiến trúc SOA
- Có ít nhất một luồng gọi REST giữa các service chạy thành công.
- Event `review.submitted` được AI Service xử lý qua Redis Streams; kết quả được phát thành event và Review Service tiếp nhận. Tài liệu hóa consumer group, retry và idempotency (xử lý lặp an toàn).
- Phát các event `booking.created` và `booking.cancelled`; có ít nhất một consumer hoặc nhật ký xử lý để quan sát luồng bất đồng bộ.
- Mỗi service sở hữu dữ liệu rõ ràng; không ghi trực tiếp vào bảng dữ liệu của service khác.
- Có thể chạy môi trường cục bộ bằng `docker compose up --build` sau khi cấu hình `.env`.

## 5. Ranh giới các service đề xuất
1. **Auth Service:** tài khoản người dùng, mã hóa mật khẩu, cấp JWT và quy ước xác thực.
2. **Hotel Service:** danh mục khách sạn/phòng, giá, dữ liệu địa điểm gần khách sạn, mô hình đọc tình trạng phòng.
3. **Booking Service:** vòng đời đặt phòng, tính nhất quán và kiểm soát đặt trùng.
4. **Review Service:** gửi đánh giá, trạng thái hiển thị và kiểm duyệt.
5. **AI Service:** phân tích ý định tìm kiếm, kiểm duyệt review, gợi ý địa điểm; tích hợp Gemini qua adapter.
6. **API Gateway:** định tuyến request và kiểm tra xác thực ở cửa vào; đây là thành phần triển khai, không tính là service nghiệp vụ.

Places Provider Adapter là thành phần tích hợp bên trong AI Service (không bắt buộc tách thành microservice). Giao diện thống nhất dự kiến: search_nearby(latitude, longitude, radius_m, categories) -> list[Place]. Place gồm provider_id, name, category, latitude, longitude, address (nếu có), source. Các adapter ứng viên: Google Places, OSM/Overpass và SeedPlaces. Chưa chốt nhà cung cấp live; cần thử nghiệm về độ phủ dữ liệu, quota, điều khoản sử dụng và cấu hình trước khi quyết định. Nếu provider lỗi/timeout/hết quota, dùng seed fallback và ghi log; chỉ dùng cache nếu được phép theo điều khoản nhà cung cấp.

**Vấn đề thiết kế cần giải quyết:** Trong SAD và API Contracts phải xác định service nào giữ quyền quyết định cuối cùng về tồn phòng và cơ chế đặt phòng nguyên tử. Chỉ kiểm tra còn phòng trước khi đặt không đủ để ngăn đặt trùng khi có request đồng thời.

## 6. Ngoài phạm vi (P2)
- Thanh toán/hoàn tiền thật và tích hợp nền tảng đặt phòng bên thứ ba.
- Ứng dụng mobile native.
- Tự huấn luyện hoặc fine-tune mô hình AI.
- Bản đồ trực tiếp, đặt xe và cập nhật phương tiện theo thời gian thực.
- Giá động phức tạp, chương trình khách hàng thân thiết, đa tiền tệ, phân tích dữ liệu quy mô lớn.

## 7. Tính năng mở rộng nếu còn thời gian (P1)
- Trang quản trị cơ bản.
- AI hỗ trợ soạn mô tả phòng, có người duyệt trước khi công bố.
- Email thông báo và lưu lịch sử hội thoại AI.

## 8. Yêu cầu phi chức năng ban đầu
- **Khả năng tái lập:** Docker Compose khởi chạy đủ service theo cấu hình đã hướng dẫn.
- **Bảo mật:** mật khẩu lưu dưới dạng hash, secrets lấy từ biến môi trường, kiểm tra quyền ở booking/review; không đưa API key lên Git.
- **Độ tin cậy:** AI lỗi không được làm hỏng dữ liệu booking; consumer xử lý lặp an toàn và chỉ ACK sau khi xử lý thành công.
- **Khả năng quan sát:** có log đủ rõ, ưu tiên gắn request ID/event ID để truy vết.
- **Khả năng kiểm thử:** có test tự động cho quy tắc booking, xác thực, xử lý event và kiểm tra đầu ra AI; test thông thường không gọi Gemini thật.
- **Tài liệu:** các endpoint được mô tả bằng OpenAPI và có ví dụ request/response; event schema được quản lý phiên bản.

## 9. Tiêu chí thành công và nghiệm thu
1. Người dùng mới có thể đăng nhập, tìm phòng, đặt phòng, xem và hủy booking trên frontend.
2. Hệ thống ngăn được một trường hợp đặt trùng cùng phòng và khoảng ngày theo mô hình tồn phòng đã thống nhất.
3. Prompt tìm phòng bằng tiếng Việt được chuyển thành bộ lọc có cấu trúc và trả về kết quả lấy từ dữ liệu khách sạn đã lưu.
4. Review chuyển từ trạng thái chờ kiểm duyệt sang được duyệt/đánh dấu qua luồng Redis Streams, có thể quan sát được.
5. Gợi ý xung quanh chỉ chứa địa điểm trong dữ liệu mẫu và có giải thích mức độ phù hợp.
6. Toàn bộ container cần thiết khởi chạy theo hướng dẫn; các test cơ bản chạy đạt trong môi trường demo.
7. Nhóm giải thích được vì sao dùng REST và Redis Streams, đồng thời xác định được service sở hữu từng nhóm dữ liệu.

## 10. Kế hoạch 4 tuần đề xuất
| Tuần | Công việc đồng thời của cả nhóm | Mốc kiểm chứng cuối tuần |
|---|---|---|
| 1 | Cùng review SRS/SAD, thống nhất REST/event contracts; dựng repo, CI cơ bản, Docker Compose, PostgreSQL/Redis, Flask skeleton, React skeleton; tạo mock endpoint và test mẫu | Chạy được skeleton các service; frontend gọi mock; có PR đầu tiên và kiểm thử tích hợp tối thiểu |
| 2 | Phát triển đồng thời Auth/Hotel/Booking/Review, giao diện và AI skeleton; viết test cho từng chức năng; tích hợp endpoint hoàn thành ngay | Demo tìm phòng và tạo booking qua API; giao diện dùng được các API đã có |
| 3 | Hoàn thiện Gemini, Redis Streams consumer, Places Adapter và seed fallback; nối frontend với backend thật; kiểm thử liên service hằng ngày | Demo ba tính năng AI, luồng review event và luồng booking end-to-end |
| 4 | Tập trung kiểm thử hồi quy, lỗi concurrency, timeout/fallback, Docker môi trường sạch; cập nhật tài liệu và diễn tập demo | Demo tái lập được, có báo cáo kiểm thử, tài liệu và slide hoàn chỉnh |

## 11. Phân công sơ bộ (chưa gán tên)
| Vai trò luân phiên / đầu mối đề xuất | Phạm vi theo dõi chính | Cách cộng tác |
|---|---|---|
| Thành viên A | Kiến trúc, API Gateway, Auth | Pair với thành viên E cho luồng đăng nhập; review API/event của nhóm |
| Thành viên B | Hotel, dữ liệu phòng, dữ liệu địa điểm | Pair với D để tích hợp AI Search/Nearby; hỗ trợ seed và kiểm thử |
| Thành viên C | Booking, tính nhất quán, Redis Streams | Pair với B để xác nhận khả dụng; với D để kiểm tra event |
| Thành viên D | Review, AI Service, Gemini | Chia prompt/test AI cho B và C; pair với E ở giao diện AI |
| Thành viên E | React frontend, luồng người dùng, demo | Dùng mock từ tuần 1; pair với các owner API khi tích hợp |

## 12. Rủi ro và biện pháp giảm thiểu
| Rủi ro | Ảnh hưởng | Biện pháp |
|---|---|---|
| Hết quota hoặc lỗi Gemini API | Không demo được AI | Provider Interface, mock adapter và dữ liệu test cố định |
| Đặt trùng phòng | Sai nghiệp vụ | Thiết kế đặt phòng nguyên tử và kiểm thử đồng thời |
| Hợp đồng liên service không rõ | Chậm tích hợp | Chốt OpenAPI/event schema ngay tuần 1 |
| Redis giao message lặp | Thay đổi trạng thái nhiều lần | Consumer idempotent, lưu trạng thái xử lý |
| Quá nhiều chức năng trong 4 tuần | Demo không hoàn chỉnh | Đóng băng P0 sau tuần 1, hoãn P1/P2 |
| Phân chia công việc mất cân đối | Trễ milestone | Rà soát tải công việc và điều chỉnh hằng tuần |

## 13. Giả định và quyết định còn mở
- **Giả định**: Nhóm có API key và quota Gemini đủ cho demo.
- **Hướng thiết kế:** Gợi ý địa điểm ưu tiên nguồn live qua Places Provider Adapter; chưa chọn Google Places hay OSM/Overpass. Seed data có tọa độ dùng làm fallback và phục vụ test/demo ổn định.
- **Chưa chốt:** Provider live cuối cùng, ngân sách/quota, điều khoản caching và dữ liệu địa điểm tại khu vực demo. Cần làm spike kỹ thuật sớm để đánh giá.
- **Đề xuất:** Năm service nghiệp vụ và một API Gateway; sẽ xác nhận khi review SAD.
- **Đề xuất:** Frontend chỉ dành cho khách hàng; dữ liệu quản trị tạo qua seed script/API.
- **Chưa chốt:** Mô hình tồn phòng và cách kiểm soát booking đồng thời.
- **Chưa chốt:** Chỉ khách đã lưu trú mới được review hay mọi tài khoản đăng nhập đều có thể review.
- **Chưa chốt:** Quy ước tên/phiên bản event, retention, retry và xử lý event lỗi.
- **Chưa chốt:** Phát triển song song, ownership linh hoạt và tích hợp liên tục từ tuần 1.
- **Chưa chốt:** Tên thành viên, lịch họp định kỳ và ngày nộp chính xác.

## 14. Quản lý thay đổi
Mọi thay đổi đối với phạm vi P0 hoặc công nghệ đã chốt phải ghi lại ngày thay đổi, lý do, người phụ trách và tác động đến API contracts, dữ liệu, tiến độ và demo.

## 15. Các tài liệu tiếp theo
1. `02-SRS.md` — Actors, use cases, yêu cầu chức năng/phi chức năng, acceptance tests.
2. `03-SAD.md` — Sơ đồ triển khai, ownership dữ liệu, tính nhất quán booking, Redis consumers.
3. `04-api-events.md` — REST endpoints, OpenAPI và event payloads.
4. `05-data-design.md` — Thiết kế schema/ERD và ownership.
5. `06-AI-Service-Specification.md` — Prompts, input/output schemas, đánh giá AI và fallback.
6. `07-implementation-plan.md` — Tasks, người phụ trách, phụ thuộc công việc.
7. `08-development-testing.md` — Hướng dẫn chạy local, Git conventions, kiểm thử và demo.

## 16. Mục tiêu học phần SOA và ma trận truy vết 
Nguyên tắc đánh giá: Mỗi nội dung học phần được chọn phải có 
- (a) quyết định thiết kế giải thích được
- (b) thành phần chạy được hoặc bài kiểm thử có thể thực hiện
- (c) bằng chứng để đưa vào báo cáo/demo. 
Các mục dưới đây là cam kết thiết kế và kiểm chứng dự kiến, chưa phải khẳng định đã triển khai xong.

| Bài học trong slide | Vận dụng cụ thể vào HotelGenie | Minh chứng tối thiểu khi nghiệm thu |
|---|---|---|
| **B1 — API và Web Services** | Phân biệt giao diện người dùng, API Gateway, các service nghiệp vụ; mô tả service contract và tương tác service-to-service | Sơ đồ thành phần; bảng trách nhiệm/đầu vào/đầu ra từng service; demo frontend gọi API |
| **B2 — REST và HTTP Fundamentals** | Dùng HTTP methods phù hợp, resource URI, status code, header, JSON; API stateless | Bảng endpoint + method + status code; ví dụ `GET /api/v1/hotels`, `POST /api/v1/bookings`; Postman kiểm tra 200/201/400/401/404/409 |
| **B3 — API Design Principles & Best Practices** | Thiết kế URL nhất quán, validate input, chuẩn hóa lỗi, xử lý idempotency/retry phù hợp, phân trang/lọc | Quy ước API chung; request/response mẫu; test trường hợp sai dữ liệu, lỗi nghiệp vụ và request lặp |
| **B4 — API Specification và OpenAPI** | Thiết kế contract-first cho API liên service; mô tả schemas, security, error responses; cung cấp Swagger UI | File `docs/contracts/openapi-public.yaml`, `docs/contracts/openapi-internal.yaml` theo OpenAPI 3.0; Swagger UI chạy được; lint và contract/schema test |
| **B5 — Data Modeling & Resource Design** | Thiết kế Hotel, Room, Booking, Review, User theo nghiệp vụ; tách API resource khỏi bảng DB; xác định service sở hữu dữ liệu | ERD; bảng ownership; SQLAlchemy models/migrations; API filtering/pagination; không truy cập trực tiếp bảng của service khác |
| **B6 — Authentication & Authorization** | Auth Service cấp/kiểm JWT; phân quyền người dùng và quyền truy cập booking/review của chính mình | Sơ đồ login/token; test 401 khi thiếu token, 403 khi không có quyền; không lưu mật khẩu dạng rõ |
| **B7 — Backend Service** | Flask Application Factory, Blueprints, service/repository layers, SQLAlchemy, cấu hình môi trường, logging/healthcheck, Docker | Cấu trúc repo; chạy độc lập các service bằng Docker Compose; endpoint health; test Flask client |
| **B8 — API Testing & QA** | Unit, integration, contract, E2E và kiểm thử tải mức phù hợp; test cả happy/error/edge cases | Pytest; Postman collection chạy Newman; kết quả test lưu được; đo latency/error rate bằng Locust nếu đủ thời gian |
| **B9 — API Versioning & Lifecycle** | Dùng URI versioning `/api/v1`; quy định breaking vs non-breaking change; minh họa kế hoạch nâng cấp | Contract có version; tài liệu migration v1→v2 và **một ví dụ tương thích ngược nhỏ** hoặc test chứng minh không phá client cũ |
| **Tích hợp SOA xuyên suốt** | REST đồng bộ cho truy vấn/lệnh; Redis Streams bất đồng bộ cho `booking.created`, `booking.cancelled`, `review.submitted`; ranh giới service rõ; consumer idempotent | Sơ đồ sequence REST/event; producer/consumer chạy được; test event trùng, service tạm lỗi và khôi phục; giải thích vì sao chọn REST hay event |

### 16.1. Các kịch bản demo phải làm rõ kiến thức SOA
1. Tìm phòng: React → Gateway → Hotel Service qua REST; AI Service phân tích prompt thành bộ lọc, Hotel Service trả dữ liệu phòng thực tế. Chứng minh REST, contract, resource design và tách trách nhiệm AI/nghiệp vụ.
2. Đặt phòng: Client gửi POST /api/v1/bookings có JWT; Booking Service kiểm tra điều kiện và tạo booking an toàn; phát booking.created qua Redis Streams. Chứng minh AuthN/AuthZ, HTTP semantics, dữ liệu sở hữu riêng và giao tiếp bất đồng bộ.
3. Đánh giá: Client tạo review qua REST; Review Service phát review.submitted; AI Service xử lý và cập nhật trạng thái kiểm duyệt qua API/luồng tích hợp được định nghĩa. Chứng minh event contract, xử lý trùng event, eventual consistency và kiểm thử liên service.
4. Nearby: AI Service gọi Places Provider Adapter; chạy thử provider live (nếu sẵn sàng) và mô phỏng provider lỗi để chuyển sang seed fallback. Chứng minh loose coupling, abstraction, timeout/failure handling.
5. Thay đổi hợp đồng API: Trình bày một thay đổi v1→v2 có tác động đến consumer, cách duy trì v1 hoặc kế hoạch migration; chạy contract test tương ứng. Chứng minh kiến thức B9, không cần xây toàn bộ API v2.

### 16.2. Quy tắc thiết kế
- Mỗi service có trách nhiệm nghiệp vụ rõ, hợp đồng công khai và quyền sở hữu dữ liệu; không gọi trực tiếp repository/database của service khác.
- Không biến API Gateway thành nơi chứa logic đặt phòng, kiểm duyệt hay xử lý AI; gateway chỉ đảm nhận chức năng truy cập/chuyển tiếp và các cross-cutting concerns được thống nhất.
- Không dùng Redis Streams chỉ để “có công nghệ”: mỗi event phải có producer, consumer, schema, ý nghĩa nghiệp vụ và chiến lược xử lý lặp/lỗi.
- Booking phải có cơ chế tránh đặt trùng dựa trên ràng buộc/giao dịch phù hợp; không giả định event bất đồng bộ tự bảo đảm tính nhất quán tồn phòng.
- Ghi rõ giới hạn: hệ thống demo học phần, không tuyên bố đạt chuẩn production nếu chưa có bằng chứng.

### 16.3. Hồ sơ bằng chứng và phân bổ trong tài liệu
- 02-SRS.md: yêu cầu SOA có mã ID và tiêu chí nghiệm thu liên quan.
- 03-SAD.md: service boundaries, deployment diagram, sequence REST/Redis, data ownership, trade-offs.
- 04-api-events.md: OpenAPI, event schemas, HTTP status, auth, versioning và quy ước lỗi.
- 05-data-design.md: ERD, migration, resource mapping, chống booking trùng.
- 06-AI-Service-Specification.md: AI contracts, provider adapters, đánh giá chất lượng, fallback.
- 07-implementation-plan.md: task SOA phân tán cho cả 5 thành viên, tích hợp từ tuần 1.
- 08-development-testing.md: hướng dẫn tái lập demo, test results, Newman, kiểm thử contract/event và báo cáo đo đạc.