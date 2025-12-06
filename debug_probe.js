const net = require('net');

const HOST = '10.244.0.46'; // I need to get the actual IP
const PORT = 5901;

console.log(`Probing ${HOST}:${PORT}...`);

const socket = new net.Socket();
socket.setTimeout(2000);

socket.connect(PORT, HOST, () => {
    console.log('Connected!');
});

socket.on('data', (data) => {
    console.log('Data received:', data.toString());
    socket.destroy();
});

socket.on('timeout', () => {
    console.log('Timeout!');
    socket.destroy();
});

socket.on('error', (err) => {
    console.log('Error:', err.message);
});
