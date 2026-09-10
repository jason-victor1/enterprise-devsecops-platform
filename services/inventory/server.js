const http = require('http');

const PORT = process.env.PORT || 8081;

if (process.argv.includes('--health')) {
  const req = http.request(
    {
      host: '127.0.0.1',
      port: PORT,
      path: '/healthz',
      method: 'GET',
      timeout: 2000,
    },
    (res) => {
      process.exit(res.statusCode === 200 ? 0 : 1);
    }
  );
  req.on('error', () => process.exit(1));
  req.end();
  return;
}

const inventoryStore = {
  'item-1': 100,
  'item-2': 50,
};

const server = http.createServer((req, res) => {
  if (req.method === 'GET' && req.url === '/healthz') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    return res.end(JSON.stringify({ status: 'healthy', service: 'inventory' }));
  }

  if (req.method === 'POST' && req.url === '/deduct') {
    let body = '';
    req.on('data', (chunk) => {
      body += chunk;
      if (body.length > 1e6) {
        req.socket.destroy();
      }
    });

    return req.on('end', () => {
      try {
        const payload = JSON.parse(body || '{}');
        const { itemId, quantity } = payload;
        if (!itemId || typeof quantity !== 'number') {
          res.writeHead(400, { 'Content-Type': 'application/json' });
          return res.end(JSON.stringify({ error: 'Invalid payload schema' }));
        }

        const currentStock = inventoryStore[itemId] || 0;
        if (currentStock < quantity) {
          res.writeHead(409, { 'Content-Type': 'application/json' });
          return res.end(JSON.stringify({ error: 'Insufficient stock', itemId, available: currentStock }));
        }

        inventoryStore[itemId] -= quantity;
        res.writeHead(200, { 'Content-Type': 'application/json' });
        return res.end(JSON.stringify({ status: 'deducted', itemId, remaining: inventoryStore[itemId] }));
      } catch (err) {
        res.writeHead(400, { 'Content-Type': 'application/json' });
        return res.end(JSON.stringify({ error: 'Malformed JSON payload' }));
      }
    });
  }

  res.writeHead(404, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify({ error: 'Endpoint not found' }));
});

server.listen(PORT, '0.0.0.0', () => {
  console.log(`Inventory service listening on port ${PORT}`);
});
