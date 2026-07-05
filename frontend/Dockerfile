FROM node:18-alpine as base

WORKDIR /app

# Copy package files
COPY package*.json ./

# Development stage with Vite dev server
FROM base AS development
ENV NODE_ENV=development

# Install all dependencies
RUN npm install

# Copy application code
COPY . .

EXPOSE 3000 5173

# Use Vite dev server for development
CMD ["npm", "run", "dev", "--", "--host", "0.0.0.0"]

# Builder stage for production
FROM base as builder
ARG VITE_DEFAULT_VR=false
ENV VITE_DEFAULT_VR=${VITE_DEFAULT_VR}

# Install dependencies
RUN npm install

# Copy application code
COPY . .

# Build the application with optional VR mode
RUN if [ "$VITE_DEFAULT_VR" = "true" ]; then npm run build:vr; else npm run build; fi

# Production stage
FROM node:18-slim AS production

# Install nginx and gettext
RUN apt-get update && apt-get install -y nginx gettext-base && rm -rf /var/lib/apt/lists/*

# Copy built app
COPY --from=builder /app/dist /usr/share/nginx/html

# Create config directory for mounted configmap
RUN mkdir -p /usr/share/nginx/html/config

# Copy nginx configurations (both static and template)
COPY --from=builder /app/nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=builder /app/nginx.conf.template /etc/nginx/templates/default.conf.template

# Create entrypoint script
COPY --from=builder /app/docker-entrypoint.sh /docker-entrypoint.sh
RUN sed -i 's/\r$//' /docker-entrypoint.sh && chmod +x /docker-entrypoint.sh

EXPOSE 3000

ENTRYPOINT ["/docker-entrypoint.sh"]
CMD ["nginx", "-g", "daemon off;"]
