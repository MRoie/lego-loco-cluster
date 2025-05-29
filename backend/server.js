// Entry for Node.js backend (Express + ws placeholder)
const express = require('express');
const path = require('path');
const app = express();

// Serve frontend static build
app.use(express.static(path.join(__dirname, '../frontend/dist')));

// TODO: Add websocket/VNC proxy logic here

app.listen(3001, () => {
  console.log('Backend running on http://localhost:3001');
});
