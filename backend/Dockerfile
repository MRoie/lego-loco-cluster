FROM node:18-alpine

WORKDIR /app

# Copy package files
COPY package*.json ./

# Install dependencies
RUN npm install --only=production

# Copy application code
COPY . .

# Create config directory for mounted configmap
RUN mkdir -p config

EXPOSE 3001

CMD ["node", "server.js"]
