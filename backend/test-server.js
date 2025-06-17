const express = require("express");
const http = require("http");

const app = express();
const server = http.createServer(app);

// simple health endpoint for Kubernetes-style checks
app.get("/health", (req, res) => {
  console.log("Health check requested");
  res.json({ status: "ok" });
});

app.get("/test", (req, res) => {
  console.log("Test endpoint requested");
  res.json({ message: "test works" });
});

// Start HTTP services
server.listen(3001, () => {
  console.log("Test Backend running on http://localhost:3001");
});

// Add uncaught exception handlers
process.on('uncaughtException', (err) => {
  console.error('Uncaught Exception:', err);
});

process.on('unhandledRejection', (reason, promise) => {
  console.error('Unhandled Rejection at:', promise, 'reason:', reason);
});
