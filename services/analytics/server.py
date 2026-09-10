import json
import os
import sys
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, HTTPServer

PORT = int(os.environ.get("PORT", 8085))

if "--health" in sys.argv:
    try:
        req = urllib.request.Request(f"http://127.0.0.1:{PORT}/healthz", method="GET")
        with urllib.request.urlopen(req, timeout=2) as response:
            sys.exit(0 if response.status == 200 else 1)
    except Exception:
        sys.exit(1)


class AnalyticsHandler(BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        sys.stdout.write(f"{self.address_string()} - [{self.log_date_time_string()}] {format % args}\n")
        sys.stdout.flush()

    def do_GET(self):
        if self.path == "/healthz":
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(json.dumps({"status": "healthy", "service": "analytics"}).encode("utf-8"))
            return

        if self.path == "/aggregate":
            orders_url = os.environ.get("ORDERS_SERVICE_URL", "http://orders:8082")
            payment_url = os.environ.get("PAYMENT_SERVICE_URL", "http://payment:8083")

            orders_status = self.check_upstream(f"{orders_url}/healthz")
            payment_status = self.check_upstream(f"{payment_url}/healthz")

            payload = {
                "service": "analytics",
                "telemetry": {
                    "ordersOperational": orders_status,
                    "paymentOperational": payment_status,
                    "aggregatedMetrics": {"totalProcessed": 1024, "processingLatencyMs": 18.4},
                },
            }

            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(json.dumps(payload).encode("utf-8"))
            return

        self.send_response(404)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(json.dumps({"error": "Resource not found"}).encode("utf-8"))

    @staticmethod
    def check_upstream(url):
        try:
            req = urllib.request.Request(url, method="GET")
            with urllib.request.urlopen(req, timeout=2) as response:
                return response.status == 200
        except Exception:
            return False


def run():
    server_address = ("0.0.0.0", PORT)
    httpd = HTTPServer(server_address, AnalyticsHandler)
    print(f"Analytics engine bound to port {PORT}")
    sys.stdout.flush()
    httpd.serve_forever()


if __name__ == "__main__":
    run()
