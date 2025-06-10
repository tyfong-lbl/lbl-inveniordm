# OpenSearch Security Implementation Plan - Localhost HTTPS Development

## Background
- Current status: OpenSearch Security plugin is installed but disabled
- Warning: "[2025-05-16T19:38:36,536][WARN ][o.o.s.OpenSearchSecurityPlugin] OpenSearch Security plugin installed but disabled. This can expose your configuration (including passwords) to the public."
- Objective: Enable security features with HTTPS for localhost-only development environment
- Setup: InvenioRDM runs on host in virtual environment, services in Docker containers
- Access: All services bound to 127.0.0.1 only, HTTPS via nginx SSL termination on port 5000


## Step 1: Create SSL Certificate Infrastructure

Create a centralized certificate directory and generation script for all services:

```bash
# Create SSL certificate directory
mkdir -p ./docker/ssl

# Create certificate generation script
cat > ./docker/ssl/generate-certs.sh << 'EOF'
#!/bin/bash

# Generate SSL certificates for localhost development
set -e

CERT_DIR="./docker/ssl"
mkdir -p "$CERT_DIR"
cd "$CERT_DIR"

echo "Generating SSL certificates for localhost development..."

# Generate CA private key
openssl genrsa -out ca-key.pem 4096

# Generate CA certificate
openssl req -new -x509 -sha256 -key ca-key.pem -out ca.pem -days 3650 \
  -subj "/C=US/ST=California/L=Berkeley/O=LBNL/OU=Development/CN=LBNL-Dev-CA"

# Generate server private key
openssl genrsa -out server-key.pem 4096

# Generate server certificate request
openssl req -new -key server-key.pem -out server.csr \
  -subj "/C=US/ST=California/L=Berkeley/O=LBNL/OU=Development/CN=localhost"

# Create extensions file for SAN
cat > server.ext << EOF
subjectAltName = DNS:localhost,DNS:*.localhost,IP:127.0.0.1,DNS:search,DNS:cache,DNS:db,DNS:mq
keyUsage = keyEncipherment, dataEncipherment
extendedKeyUsage = serverAuth, clientAuth
EOF

# Generate server certificate
openssl x509 -req -in server.csr -CA ca.pem -CAkey ca-key.pem \
  -CAcreateserial -sha256 -out server.pem -days 3650 -extfile server.ext

# Generate client certificate for OpenSearch admin
openssl genrsa -out admin-key.pem 4096
openssl req -new -key admin-key.pem -out admin.csr \
  -subj "/C=US/ST=California/L=Berkeley/O=LBNL/OU=Development/CN=admin"
openssl x509 -req -in admin.csr -CA ca.pem -CAkey ca-key.pem \
  -CAcreateserial -sha256 -out admin.pem -days 3650

# Set proper permissions
chmod 600 *.pem *.key
chmod 644 ca.pem server.pem admin.pem

echo "Certificates generated successfully!"
echo "To trust the CA in your browser, import: $PWD/ca.pem"
EOF

# Make script executable
chmod +x ./docker/ssl/generate-certs.sh
```


## Step 2: Configure Nginx Frontend for HTTPS Termination

Create nginx configuration for SSL termination and proxy to host-based InvenioRDM:

```bash
# Create nginx configuration
mkdir -p ./docker/nginx

cat > ./docker/nginx/nginx.conf << 'EOF'
upstream backend {
    server host.docker.internal:5000;
}

server {
    listen 443 ssl http2;
    server_name localhost;

    # SSL Configuration
    ssl_certificate /etc/ssl/certs/server.pem;
    ssl_certificate_key /etc/ssl/private/server-key.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-RSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-RSA-AES128-SHA256:ECDHE-RSA-AES256-SHA384;
    ssl_prefer_server_ciphers on;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;

    # Security headers
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header X-Frame-Options DENY always;
    add_header X-Content-Type-Options nosniff always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;

    # Client max body size
    client_max_body_size 100M;

    # Proxy settings
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_set_header X-Forwarded-Host $host;
    proxy_set_header X-Forwarded-Port $server_port;

    location / {
        proxy_pass http://backend;
        proxy_redirect off;
        
        # WebSocket support
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}

# Redirect HTTP to HTTPS
server {
    listen 80;
    server_name localhost;
    return 301 https://$server_name$request_uri;
}
EOF

# Update nginx Dockerfile
cat > ./docker/nginx/Dockerfile << 'EOF'
FROM nginx:alpine

# Copy nginx configuration
COPY nginx.conf /etc/nginx/conf.d/default.conf

# Create directories for SSL files
RUN mkdir -p /etc/ssl/certs /etc/ssl/private

EXPOSE 80 443
EOF
```


## Step 3: Update Docker Compose for Localhost-Only Access

Update `docker-compose.yml` to bind all services to localhost only:

```yaml
# Backend services for localhost-only HTTPS development
version: '2.2'

networks:
  internal-net:
    driver: bridge
    driver_opts:
      com.docker.network.bridge.name: "invenio-dev"

services:
  cache:
    extends:
      file: docker-services.yml
      service: cache
    ports:
      - "127.0.0.1:6379:6379"
    networks:
      - internal-net

  db:
    extends:
      file: docker-services.yml
      service: db
    ports:
      - "127.0.0.1:5432:5432"
    networks:
      - internal-net

  mq:
    extends:
      file: docker-services.yml
      service: mq
    ports:
      - "127.0.0.1:15672:15672"
      - "127.0.0.1:5672:5672"
    networks:
      - internal-net

  search:
    extends:
      file: docker-services.yml
      service: search
    ports:
      - "127.0.0.1:9200:9200"
      - "127.0.0.1:9600:9600"
    networks:
      - internal-net

  opensearch-dashboards:
    extends:
      file: docker-services.yml
      service: opensearch-dashboards
    ports:
      - "127.0.0.1:5601:5601"
    networks:
      - internal-net

  pgadmin:
    extends:
      file: docker-services.yml
      service: pgadmin
    ports:
      - "127.0.0.1:5050:80"
    networks:
      - internal-net

  frontend:
    extends:
      file: docker-services.yml
      service: frontend
    ports:
      - "127.0.0.1:5000:443"
    networks:
      - internal-net
    depends_on:
      - search
      - cache
      - db
      - mq
```


## Step 4: Configure OpenSearch with SSL Security

Update `docker-services.yml` for secure OpenSearch configuration:

```yaml
  search:
    image: opensearchproject/opensearch:2.17.1
    restart: "unless-stopped"
    environment:
      # Security settings
      - "DISABLE_SECURITY_PLUGIN=false"
      - "OPENSEARCH_JAVA_OPTS=-Xms512m -Xmx512m"
      - "plugins.security.ssl.http.enabled=true"
      - "plugins.security.ssl.transport.enabled=true"
      - "plugins.security.ssl.http.pemcert_filepath=config/certificates/server.pem"
      - "plugins.security.ssl.http.pemkey_filepath=config/certificates/server-key.pem"
      - "plugins.security.ssl.http.pemtrustedcas_filepath=config/certificates/ca.pem"
      - "plugins.security.ssl.transport.pemcert_filepath=config/certificates/server.pem"
      - "plugins.security.ssl.transport.pemkey_filepath=config/certificates/server-key.pem"
      - "plugins.security.ssl.transport.pemtrustedcas_filepath=config/certificates/ca.pem"
      - "plugins.security.allow_default_init_securityindex=true"
      - "plugins.security.authcz.admin_dn=[\"CN=admin,OU=Development,O=LBNL,L=Berkeley,ST=California,C=US\"]"
      - "plugins.security.nodes_dn=[\"CN=localhost,OU=Development,O=LBNL,L=Berkeley,ST=California,C=US\"]"
      - "plugins.security.audit.type=internal_opensearch"
      - "plugins.security.enable_snapshot_restore_privilege=true"
      - "plugins.security.check_snapshot_restore_write_privileges=true"
      - "plugins.security.restapi.roles_enabled=[\"all_access\", \"security_rest_api_access\"]"
      # Other settings
      - "bootstrap.memory_lock=true"
      - "discovery.type=single-node"
      - "OPENSEARCH_INITIAL_ADMIN_PASSWORD=${OPENSEARCH_ADMIN_PASSWORD}"
    volumes:
      - ./docker/ssl:/usr/share/opensearch/config/certificates:ro
    ulimits:
      memlock:
        soft: -1
        hard: -1
      nofile:
        soft: 65536
        hard: 65536
    mem_limit: 2g
```


## Step 5: Configure OpenSearch Dashboards with HTTPS

Update `docker-services.yml` for OpenSearch Dashboards:

```yaml
  opensearch-dashboards:
    restart: "unless-stopped"
    image: opensearchproject/opensearch-dashboards:2.17.1
    environment:
      - "DISABLE_SECURITY_DASHBOARDS_PLUGIN=false"
      - "OPENSEARCH_HOSTS=https://search:9200"
      - "OPENSEARCH_SSL_VERIFICATIONMODE=certificate"
      - "OPENSEARCH_SSL_CERTIFICATEAUTHORITIES=/usr/share/opensearch-dashboards/config/certificates/ca.pem"
      - "OPENSEARCH_USERNAME=${OPENSEARCH_ADMIN_USER:-admin}"
      - "OPENSEARCH_PASSWORD=${OPENSEARCH_ADMIN_PASSWORD}"
      - "SERVER_SSL_ENABLED=true"
      - "SERVER_SSL_CERTIFICATE=/usr/share/opensearch-dashboards/config/certificates/server.pem"
      - "SERVER_SSL_KEY=/usr/share/opensearch-dashboards/config/certificates/server-key.pem"
    volumes:
      - ./docker/ssl:/usr/share/opensearch-dashboards/config/certificates:ro

  frontend:
    build: 
      context: ./docker/nginx/
      dockerfile: Dockerfile
    image: lbnl-data-repository-frontend
    restart: "unless-stopped"
    volumes:
      - ./docker/ssl/server.pem:/etc/ssl/certs/server.pem:ro
      - ./docker/ssl/server-key.pem:/etc/ssl/private/server-key.pem:ro
    extra_hosts:
      - "host.docker.internal:host-gateway"
```


## Step 6: Update InvenioRDM Configuration for Localhost HTTPS

Update your `invenio.cfg` file to use environment variables and localhost connections:

```python
# HTTPS and SSL Configuration
import os

# OpenSearch credentials from environment
OPENSEARCH_ADMIN_USER = os.environ.get('OPENSEARCH_ADMIN_USER', 'admin')
OPENSEARCH_ADMIN_PASSWORD = os.environ.get('OPENSEARCH_ADMIN_PASSWORD')

if not OPENSEARCH_ADMIN_PASSWORD:
    raise ValueError("OPENSEARCH_ADMIN_PASSWORD environment variable must be set")

# Search client configuration for HTTPS OpenSearch
SEARCH_CLIENT_CONFIG = {
    "hosts": ["https://127.0.0.1:9200"],
    "http_auth": (OPENSEARCH_ADMIN_USER, OPENSEARCH_ADMIN_PASSWORD),
    "use_ssl": True,
    "verify_certs": True,
    "ca_certs": os.path.join(os.path.dirname(__file__), "docker/ssl/ca.pem"),
    "ssl_show_warn": False
}

# Database configuration - credentials from environment
DB_USER = os.environ.get('POSTGRES_USER', 'lbnl-data-repository')
DB_PASSWORD = os.environ.get('POSTGRES_PASSWORD', 'lbnl-data-repository')
DB_NAME = os.environ.get('POSTGRES_DB', 'lbnl-data-repository')
DB_HOST = os.environ.get('POSTGRES_HOST', '127.0.0.1')
DB_PORT = os.environ.get('POSTGRES_PORT', '5432')

SQLALCHEMY_DATABASE_URI = f"postgresql+psycopg2://{DB_USER}:{DB_PASSWORD}@{DB_HOST}:{DB_PORT}/{DB_NAME}"

# Redis configuration
REDIS_HOST = os.environ.get('REDIS_HOST', '127.0.0.1')
REDIS_PORT = os.environ.get('REDIS_PORT', '6379')

CACHE_REDIS_URL = f"redis://{REDIS_HOST}:{REDIS_PORT}/0"
ACCOUNTS_SESSION_REDIS_URL = f"redis://{REDIS_HOST}:{REDIS_PORT}/1"
CELERY_RESULT_BACKEND = f"redis://{REDIS_HOST}:{REDIS_PORT}/2"
RATELIMIT_STORAGE_URL = f"redis://{REDIS_HOST}:{REDIS_PORT}/3"

# RabbitMQ configuration
RABBITMQ_HOST = os.environ.get('RABBITMQ_HOST', '127.0.0.1')
RABBITMQ_PORT = os.environ.get('RABBITMQ_PORT', '5672')
RABBITMQ_USER = os.environ.get('RABBITMQ_USER', 'guest')
RABBITMQ_PASSWORD = os.environ.get('RABBITMQ_PASSWORD', 'guest')

CELERY_BROKER_URL = f"amqp://{RABBITMQ_USER}:{RABBITMQ_PASSWORD}@{RABBITMQ_HOST}:{RABBITMQ_PORT}/"
BROKER_URL = f"amqp://{RABBITMQ_USER}:{RABBITMQ_PASSWORD}@{RABBITMQ_HOST}:{RABBITMQ_PORT}/"

# Security settings
APP_ALLOWED_HOSTS = ["127.0.0.1", "localhost"]
```


## Step 7: Environment Variables Setup

Add these environment variables to your development environment script:

```bash
#!/bin/bash
# Development environment variables

# OpenSearch Security Credentials
export OPENSEARCH_ADMIN_USER="admin"
export OPENSEARCH_ADMIN_PASSWORD="YourComplexPassword123!@#"

# Optional: Override default database credentials if needed
export POSTGRES_USER="lbnl-data-repository"
export POSTGRES_PASSWORD="lbnl-data-repository"
export POSTGRES_DB="lbnl-data-repository"
export POSTGRES_HOST="127.0.0.1"
export POSTGRES_PORT="5432"

# Optional: Override Redis settings
export REDIS_HOST="127.0.0.1"
export REDIS_PORT="6379"

# Optional: Override RabbitMQ credentials
export RABBITMQ_HOST="127.0.0.1"
export RABBITMQ_PORT="5672"
export RABBITMQ_USER="guest"
export RABBITMQ_PASSWORD="guest"

echo "Development environment variables loaded"
```

**Security Note:** Never commit credentials to version control. Use strong, unique passwords for each service.


## Step 8: Browser Certificate Trust Setup

To avoid browser security warnings for HTTPS development:

```bash
# After generating certificates, import the CA certificate to your browser
echo "Import the CA certificate to trust HTTPS connections:"
echo "Certificate location: ./docker/ssl/ca.pem"
echo ""
echo "For Chrome/Edge:"
echo "1. Go to Settings → Privacy and Security → Security → Manage Certificates"
echo "2. Click 'Authorities' tab"
echo "3. Click 'Import' and select ca.pem"
echo "4. Check 'Trust this certificate for identifying websites'"
echo ""
echo "For Firefox:"
echo "1. Go to Settings → Privacy & Security → Certificates → View Certificates"
echo "2. Click 'Authorities' tab"
echo "3. Click 'Import' and select ca.pem"
echo "4. Check 'Trust this CA to identify websites'"
```


## Step 9: Implementation Steps

Follow these steps to implement the secure localhost HTTPS setup:

```bash
# 1. Generate SSL certificates
./docker/ssl/generate-certs.sh

# 2. Import CA certificate to your browser (see Step 8)

# 3. Stop any running containers
docker-compose down

# 4. Source your environment variables
source your_env_script.sh

# 5. Start services with new configuration
docker-compose up -d

# 6. Wait for services to start (especially OpenSearch)
sleep 30

# 7. Verify services are running
docker-compose ps

# 8. Test HTTPS access
curl -k https://localhost:5000
curl -k -u admin:YourComplexPassword123!@# https://localhost:9200
curl -k https://localhost:5601
```

**Verification checklist:**
- [ ] All services accessible only from localhost
- [ ] InvenioRDM available at `https://localhost:5000`
- [ ] OpenSearch Dashboards at `https://localhost:5601`
- [ ] OpenSearch API at `https://localhost:9200`
- [ ] PgAdmin at `http://localhost:5050`
- [ ] RabbitMQ Management at `http://localhost:15672`
- [ ] No external network access to any service
- [ ] Browser trusts HTTPS certificate (no warnings)


## Security Considerations

This localhost-only HTTPS development setup provides:

- **Network isolation**: All services bound to 127.0.0.1 only - no external access possible
- **HTTPS encryption**: End-to-end encryption for all web traffic via nginx SSL termination
- **Certificate security**: Self-signed certificates with proper SAN configuration
- **Credential protection**: All passwords in environment variables, not committed to repo
- **Service authentication**: OpenSearch secured with username/password authentication
- **Transport security**: Internal service communication uses SSL where supported
- **Development convenience**: Single certificate for all services, trusted by browser
- **Production similarity**: HTTPS setup mirrors production environment configuration

**Maintenance requirements:**
- Regenerate certificates annually (current validity: 10 years)
- Rotate passwords regularly
- Keep environment variables secure and never commit to version control
- Monitor for any services accidentally exposed to external interfaces
- Update certificate paths if directory structure changes

