FROM nginx:alpine
COPY nginx.conf /etc/nginx/conf.d/default.conf
# Create directories for SSL files
RUN mkdir -p /etc/ssl/certs /etc/ssl/private

EXPOSE 80 443
