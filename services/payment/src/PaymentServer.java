package services.payment.src;

import com.sun.net.httpserver.HttpExchange;
import com.sun.net.httpserver.HttpHandler;
import com.sun.net.httpserver.HttpServer;

import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.InetSocketAddress;
import java.net.URI;
import java.net.URL;
import java.nio.charset.StandardCharsets;
import java.util.UUID;
import java.util.concurrent.Executors;

public class PaymentServer {
    public static void main(String[] args) throws Exception {
        int port = 8083;

        if (args.length > 0 && "--health".equals(args[0])) {
            try {
                URL url = URI.create("http://127.0.0.1:" + port + "/healthz").toURL();
                HttpURLConnection conn = (HttpURLConnection) url.openConnection();
                conn.setConnectTimeout(2000);
                conn.setReadTimeout(2000);
                conn.setRequestMethod("GET");
                int code = conn.getResponseCode();
                System.exit(code == 200 ? 0 : 1);
            } catch (Exception e) {
                System.exit(1);
            }
        }

        HttpServer server = HttpServer.create(new InetSocketAddress(port), 0);

        server.createContext("/healthz", new HttpHandler() {
            @Override
            public void handle(HttpExchange exchange) throws IOException {
                byte[] response = "{\"status\":\"healthy\",\"service\":\"payment\"}".getBytes(StandardCharsets.UTF_8);
                exchange.getResponseHeaders().set("Content-Type", "application/json");
                exchange.sendResponseHeaders(200, response.length);
                try (OutputStream os = exchange.getResponseBody()) {
                    os.write(response);
                }
            }
        });

        server.createContext("/process", new HttpHandler() {
            @Override
            public void handle(HttpExchange exchange) throws IOException {
                if (!"POST".equalsIgnoreCase(exchange.getRequestMethod())) {
                    exchange.sendResponseHeaders(405, -1);
                    return;
                }

                InputStream is = exchange.getRequestBody();
                String body = new String(is.readAllBytes(), StandardCharsets.UTF_8);

                String notificationUrl = System.getenv("NOTIFICATION_SERVICE_URL");
                if (notificationUrl == null || notificationUrl.isEmpty()) {
                    notificationUrl = "http://notification:8084";
                }

                try {
                    URL target = URI.create(notificationUrl + "/notify").toURL();
                    HttpURLConnection conn = (HttpURLConnection) target.openConnection();
                    conn.setRequestMethod("POST");
                    conn.setDoOutput(true);
                    conn.setRequestProperty("Content-Type", "application/json");
                    conn.setConnectTimeout(3000);
                    conn.setReadTimeout(3000);

                    String notifyPayload = "{\"event\":\"payment_captured\",\"timestamp\":" + System.currentTimeMillis() + "}";
                    try (OutputStream os = conn.getOutputStream()) {
                        os.write(notifyPayload.getBytes(StandardCharsets.UTF_8));
                    }
                    int notifyStatus = conn.getResponseCode();
                    if (notifyStatus < 200 || notifyStatus >= 300) {
                        System.err.println("Warning: notification downstream failed with code " + notifyStatus);
                    }
                } catch (Exception ex) {
                    System.err.println("Notification dispatch failure: " + ex.getMessage());
                }

                String paymentId = "pay-" + UUID.randomUUID().toString();
                String jsonResponse = "{\"paymentId\":\"" + paymentId + "\",\"status\":\"captured\",\"audit\":\"" + body.hashCode() + "\"}";
                byte[] resBytes = jsonResponse.getBytes(StandardCharsets.UTF_8);

                exchange.getResponseHeaders().set("Content-Type", "application/json");
                exchange.sendResponseHeaders(200, resBytes.length);
                try (OutputStream os = exchange.getResponseBody()) {
                    os.write(resBytes);
                }
            }
        });

        server.setExecutor(Executors.newVirtualThreadPerTaskExecutor());
        System.out.println("Payment service running on port " + port);
        server.start();
    }
}
