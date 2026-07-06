const WebSocket = require('ws');

const INSTANCE_ID = 'instance-0'; // From instances.json
const TRACE_ID = 'TEST-VERIFICATION-TRACE-' + Date.now();
const BACKEND_URL = `ws://localhost:3001/proxy/vnc/${INSTANCE_ID}?traceId=${TRACE_ID}`;

console.log(`[TEST] Connecting to ${BACKEND_URL}`);

const ws = new WebSocket(BACKEND_URL);

ws.on('open', () => {
    console.log('[TEST] WebSocket Connected!');
    console.log('[TEST] Sending dummy data to trigger sniffer...');
    // Send 10 bytes (not enough for full sniffing but might trigger TCP write)
    ws.send(Buffer.from([0, 0, 0, 0]));

    setTimeout(() => {
        console.log('[TEST] closing...');
        ws.close();
        process.exit(0);
    }, 2000);
});

ws.on('error', (err) => {
    console.error('[TEST] WS Error:', err.message);
    process.exit(1);
});

ws.on('close', (code, reason) => {
    console.log(`[TEST] Closed: ${code} ${reason}`);
});
