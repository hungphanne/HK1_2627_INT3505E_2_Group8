"""Tasks API - Flask app phục vụ 5 endpoint và tài liệu OpenAPI.

Nhóm 8 - INT3505E 2:
  21021503 - Nguyễn Phan Hùng
  24021485 - Lã Việt Hoàng
"""
import datetime
import hmac
import os
import pathlib
import uuid

import yaml
from flask import Flask, Response, jsonify, request
from werkzeug.exceptions import HTTPException

BASE_DIR = pathlib.Path(__file__).parent
SPEC = yaml.safe_load((BASE_DIR / "openapi.yaml").read_text(encoding="utf-8"))

STATUSES = ("todo", "in_progress", "done")
CREATE_FIELDS = {"title", "description", "status", "dueDate"}
# Token demo cho bài lab. Đổi bằng biến môi trường TASKS_API_TOKEN.
API_TOKEN = os.environ.get("TASKS_API_TOKEN", "demo-token")

app = Flask(__name__)
app.json.ensure_ascii = False  # giữ nguyên tiếng Việt trong JSON

TASKS: dict[str, dict] = {}


class ApiError(Exception):
    def __init__(self, status: int, code: str, message: str):
        self.status, self.code, self.message = status, code, message


def error_response(status: int, code: str, message: str):
    return jsonify({"code": code, "message": message}), status


@app.errorhandler(ApiError)
def handle_api_error(e: ApiError):
    resp = error_response(e.status, e.code, e.message)
    if e.status == 401:
        resp[0].headers["WWW-Authenticate"] = "Bearer"
    return resp


@app.before_request
def require_bearer_token():
    """Chỉ bảo vệ /tasks. /docs và /openapi.json luôn mở để xem tài liệu."""
    if not request.path.startswith("/tasks"):
        return None
    header = request.headers.get("Authorization", "")
    scheme, _, token = header.partition(" ")
    if scheme.lower() != "bearer" or not hmac.compare_digest(token.strip(), API_TOKEN):
        raise ApiError(401, "UNAUTHORIZED", "Thiếu hoặc sai Bearer token")
    return None


@app.errorhandler(HTTPException)
def handle_http_error(e: HTTPException):
    code = (e.name or "ERROR").upper().replace(" ", "_")
    return error_response(e.code or 500, code, e.description or e.name)


@app.errorhandler(Exception)
def handle_unexpected(e: Exception):
    return error_response(500, "INTERNAL_ERROR", "Lỗi máy chủ")


def get_json_body() -> dict:
    body = request.get_json(silent=True)
    if not isinstance(body, dict):
        raise ApiError(400, "BAD_REQUEST", "Body phải là một JSON object")
    return body


def validate_fields(body: dict, *, require_title: bool) -> None:
    unknown = set(body) - CREATE_FIELDS
    if unknown:
        raise ApiError(400, "BAD_REQUEST", f"Trường không hợp lệ: {', '.join(sorted(unknown))}")
    if require_title and "title" not in body:
        raise ApiError(400, "BAD_REQUEST", "title là bắt buộc")
    if not body:
        raise ApiError(400, "BAD_REQUEST", "Cần ít nhất một trường để cập nhật")
    if "title" in body:
        t = body["title"]
        if not isinstance(t, str) or not 1 <= len(t) <= 200:
            raise ApiError(400, "BAD_REQUEST", "title phải là chuỗi dài 1-200 ký tự")
    if "description" in body and not isinstance(body["description"], str):
        raise ApiError(400, "BAD_REQUEST", "description phải là chuỗi")
    if "status" in body and body["status"] not in STATUSES:
        raise ApiError(400, "BAD_REQUEST", f"status phải là một trong: {', '.join(STATUSES)}")
    if "dueDate" in body:
        try:
            datetime.date.fromisoformat(body["dueDate"])
        except (TypeError, ValueError):
            raise ApiError(400, "BAD_REQUEST", "dueDate phải có dạng YYYY-MM-DD")


def find_task(task_id: str) -> dict:
    task = TASKS.get(task_id)
    if task is None:
        raise ApiError(404, "NOT_FOUND", "Task không tồn tại")
    return task


def parse_int(name: str, default: int, minimum: int, maximum: int | None = None) -> int:
    raw = request.args.get(name)
    if raw is None:
        return default
    try:
        value = int(raw)
    except ValueError:
        raise ApiError(400, "BAD_REQUEST", f"{name} phải là số nguyên")
    if value < minimum or (maximum is not None and value > maximum):
        limit = f"{minimum}-{maximum}" if maximum is not None else f">= {minimum}"
        raise ApiError(400, "BAD_REQUEST", f"{name} phải trong khoảng {limit}")
    return value


# ----- 5 endpoint -----------------------------------------------------------
@app.get("/tasks")
def list_tasks():
    status = request.args.get("status")
    if status is not None and status not in STATUSES:
        raise ApiError(400, "BAD_REQUEST", f"status phải là một trong: {', '.join(STATUSES)}")
    limit = parse_int("limit", 20, 1, 100)
    offset = parse_int("offset", 0, 0)
    matched = [t for t in TASKS.values() if status is None or t["status"] == status]
    return jsonify({"items": matched[offset:offset + limit], "total": len(matched)})


@app.post("/tasks")
def create_task():
    body = get_json_body()
    validate_fields(body, require_title=True)
    task = {
        "id": str(uuid.uuid4()),
        "title": body["title"],
        "status": body.get("status", "todo"),
        "createdAt": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    }
    for optional in ("description", "dueDate"):
        if optional in body:
            task[optional] = body[optional]
    TASKS[task["id"]] = task
    resp = jsonify(task)
    resp.status_code = 201
    resp.headers["Location"] = f"/tasks/{task['id']}"
    return resp


@app.get("/tasks/<task_id>")
def get_task(task_id: str):
    return jsonify(find_task(task_id))


@app.patch("/tasks/<task_id>")
def update_task(task_id: str):
    task = find_task(task_id)
    body = get_json_body()
    validate_fields(body, require_title=False)
    task.update(body)
    return jsonify(task)


@app.delete("/tasks/<task_id>")
def delete_task(task_id: str):
    find_task(task_id)
    del TASKS[task_id]
    return Response(status=204)


# ----- Tài liệu OpenAPI -------------------------------------------------------
@app.get("/openapi.json")
def openapi_json():
    return jsonify(SPEC)


SWAGGER_PAGE = """<!doctype html>
<html lang="vi">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Tasks API - Swagger UI</title>
  <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/swagger-ui-dist@5/swagger-ui.css">
</head>
<body>
  <div id="swagger-ui"></div>
  <script src="https://cdn.jsdelivr.net/npm/swagger-ui-dist@5/swagger-ui-bundle.js"></script>
  <script>
    window.ui = SwaggerUIBundle({
      url: "/openapi.json",
      dom_id: "#swagger-ui",
      tryItOutEnabled: true,
      persistAuthorization: true
    });
  </script>
</body>
</html>
"""


@app.get("/docs")
def docs():
    return Response(SWAGGER_PAGE, mimetype="text/html")


if __name__ == "__main__":
    app.run(debug=True)
