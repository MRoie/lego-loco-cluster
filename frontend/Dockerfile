FROM node:18-alpine as builder

WORKDIR /app

# Copy package files
COPY package*.json ./

# Install dependencies
RUN npm install

# Copy application code
COPY . .

# Build the application
RUN npm run build

# Production stage
FROM nginx:alpine

# Copy built app
COPY --from=builder /app/dist /usr/share/nginx/html

# Create config directory for mounted configmap
RUN mkdir -p /usr/share/nginx/html/config

# Copy nginx configurations (both static and template)
COPY --from=builder /app/nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=builder /app/nginx.conf.template /etc/nginx/templates/default.conf.template

# Install envsubst for template processing
RUN apk add --no-cache gettext

# Create entrypoint script
COPY --from=builder /app/docker-entrypoint.sh /docker-entrypoint.sh
RUN chmod +x /docker-entrypoint.sh

EXPOSE 3000

ENTRYPOINT ["/docker-entrypoint.sh"]
CMD ["nginx", "-g", "daemon off;"]
