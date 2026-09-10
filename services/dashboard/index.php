<?php
declare(strict_types=1);

$port = getenv('PORT') ?: '8086';

if (isset($argv[1]) && $argv[1] === '--health') {
    $ctx = stream_context_create(['http' => ['timeout' => 2]]);
    $res = @file_get_contents("http://127.0.0.1:{$port}/healthz", false, $ctx);
    exit($res !== false ? 0 : 1);
}

$path = parse_url($_SERVER['REQUEST_URI'] ?? '/', PHP_URL_PATH);

if ($path === '/healthz') {
    header('Content-Type: application/json');
    echo json_encode(['status' => 'healthy', 'service' => 'dashboard']);
    exit(0);
}

if ($path === '/') {
    $catalogUrl   = getenv('CATALOG_SERVICE_URL') ?: 'http://catalog:8080';
    $ordersUrl    = getenv('ORDERS_SERVICE_URL') ?: 'http://orders:8082';
    $analyticsUrl = getenv('ANALYTICS_SERVICE_URL') ?: 'http://analytics:8085';

    $ctx = stream_context_create(['http' => ['timeout' => 3, 'ignore_errors' => true]]);

    $catalogData   = @file_get_contents("{$catalogUrl}/items", false, $ctx) ?: '[]';
    $analyticsData = @file_get_contents("{$analyticsUrl}/aggregate", false, $ctx) ?: '{}';

    header('Content-Type: application/json');
    echo json_encode([
        'system' => 'Enterprise Production Hardened Gateway',
        'telemetry' => [
            'catalogInventory' => json_decode($catalogData, true),
            'analyticsFeed'    => json_decode($analyticsData, true)
        ],
        'links' => [
            'ordersEndpoint' => "{$ordersUrl}/orders"
        ]
    ], JSON_PRETTY_PRINT);
    exit(0);
}

http_response_code(404);
header('Content-Type: application/json');
echo json_encode(['error' => 'Endpoint not mapped']);
