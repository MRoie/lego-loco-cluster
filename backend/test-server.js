const express = require("express");
const http = require("http");
const logger = require("../utils/logger");

const app = express();
const server = http.createServer(app);

// simple health endpoint for Kubernetes-style checks
app.get("/health", (req, res) => {
  logger.info("Health check requested");
  res.json({ status: "ok" });
});

app.get("/test", (req, res) => {
  logger.info("Test endpoint requested");
  res.json({ message: "test works" });
});

// Start HTTP services
server.listen(3001, () => {
  logger.info("Test Backend running on http://localhost:3001");
});

// Add uncaught exception handlers
process.on('uncaughtException', (err) => {
  logger.error('Uncaught Exception:', err);
});

process.on('unhandledRejection', (reason, promise) => {
  logger.error('Unhandled Rejection at:', promise, 'reason:', reason);
});
