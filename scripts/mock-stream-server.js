const express = require('../backend/node_modules/express');
const { createLogger } = require('../utils/logger');

const logger = createLogger('mock-stream-server');
const app = express();
const port = process.env.PORT || 6080;

for (let i = 0; i < 9; i++) {
  app.get(`/vnc${i}`, (req, res) => {
    logger.debug("Mock stream endpoint accessed", { endpoint: `/vnc${i}`, stream: i });
    res.send(`stream ${i}`);
  });
}

app.listen(port, () => {
  logger.info("Mock stream server started", { 
    url: `http://localhost:${port}`,
    port,
    endpoints: Array.from({ length: 9 }, (_, i) => `/vnc${i}`)
  });
});
