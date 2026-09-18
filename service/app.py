"""Small dependency-free HTTP service for the platform assignment."""

import json
import os
import socket
from pathlib import Path
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


class RequestHandler(BaseHTTPRequestHandler):
    """Serve the application metadata and health endpoint."""

    def do_GET(self) -> None:  # noqa: N802 - required by BaseHTTPRequestHandler
        if self.path == "/":
            self._send_json(
                HTTPStatus.OK,
                {
                    "app": get_setting("APP_NAME", "demo-service"),
                    "version": get_setting("VERSION", "dev"),
                    "pod": socket.gethostname(),
                },
            )
            return

        if self.path == "/healthz":
            self._send_json(HTTPStatus.OK, {"status": "ok"})
            return

        self._send_json(HTTPStatus.NOT_FOUND, {"error": "not found"})

    def _send_json(self, status: HTTPStatus, body: dict[str, str]) -> None:
        payload = json.dumps(body).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def log_message(self, format: str, *args: object) -> None:
        """Keep container logs concise while retaining request information."""
        print(f"{self.client_address[0]} - {format % args}", flush=True)


def get_setting(name: str, default: str) -> str:
    """Read an env setting, or its projected ConfigMap file when mounted.

    Environment variables are the normal runtime interface.  The optional file
    takes precedence in Kubernetes so a ConfigMap update is reflected without
    needing to restart the Pod.
    """
    config_file = Path("/etc/demo-config") / name
    try:
        value = config_file.read_text(encoding="utf-8").strip()
    except OSError:
        value = ""
    return value or os.environ.get(name, default)


def main() -> None:
    port = int(os.environ.get("PORT", "8080"))
    server = ThreadingHTTPServer(("0.0.0.0", port), RequestHandler)
    print(f"Listening on port {port}", flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
