FROM node:18-alpine AS base

WORKDIR /app

# Copy package files from backend directory
COPY backend/package*.json ./

# Development stage with nodemon and dev dependencies
FROM base AS development
ENV NODE_ENV=development

# Install all dependencies including devDependencies
RUN npm install

# Copy utils from root
COPY utils /app/utils
RUN ls -la /app && ls -la /app/utils

# Copy application code from backend directory  
COPY backend/. .

# Create config directory for mounted configmap
RUN mkdir -p config

EXPOSE 3001 9229

# Use nodemon for development with file watching
CMD ["npm", "run", "monitor"]

# Production stage with minimal dependencies
FROM base AS production
ENV NODE_ENV=production

# Install only production dependencies
RUN npm install --only=production

# Copy utils from root
COPY utils /app/utils
RUN ls -la /app && ls -la /app/utils

# Copy application code from backend directory
COPY backend/. .

# Create config directory for mounted configmap
RUN mkdir -p config

EXPOSE 3001

CMD ["node", "server.js"]
