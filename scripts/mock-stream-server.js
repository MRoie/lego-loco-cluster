const express = require('../backend/node_modules/express');
const app = express();
const port = process.env.PORT || 6080;

for (let i = 0; i < 9; i++) {
  app.get(`/vnc${i}`, (req, res) => res.send(`stream ${i}`));
}

app.listen(port, () => {
  console.log(`Mock stream server listening on http://localhost:${port}`);
});
