```markdown
# OpenSearch Security Implementation Plan

## Background
- Current status: OpenSearch Security plugin is installed but disabled
- Warning: "[2025-05-16T19:38:36,536][WARN ][o.o.s.OpenSearchSecurityPlugin] OpenSearch Security plugin installed but disabled. This can expose your configuration (including passwords) to the public."
- Objective: Enable security features to protect sensitive configuration data while restricting access to the internal Docker network only

## Step 1: Modify Docker Configuration for OpenSearch

Update `docker-services.yml` for the search service:

```yaml
services:
  search:
    image: opensearchproject/opensearch:2.17.1
    restart: "unless-stopped"
    environment:
      # Security settings
      - "DISABLE_SECURITY_PLUGIN=false"
      - "OPENSEARCH_JAVA_OPTS=-Xms512m -Xmx512m -Dopensearch.allow_unsafe_democertificates=true -Dopensearch.allow_default_init_securityindex=true"
      - "plugins.security.ssl.http.enabled=true"
      - "plugins.security.ssl.transport.enabled=true"
      - "plugins.security.ssl.http.pemcert_filepath=config/certificates/node.pem"
      - "plugins.security.ssl.http.pemkey_filepath=config/certificates/node-key.pem"
      - "plugins.security.ssl.transport.pemcert_filepath=config/certificates/node.pem"
      - "plugins.security.ssl.transport.pemkey_filepath=config/certificates/node-key.pem"
      - "plugins.security.allow_default_init_securityindex=true"
      - "plugins.security.authcz.admin_dn=[\"CN=admin,OU=LBL,O=LBNL,L=Berkeley,ST=California,C=US\"]"
      - "plugins.security.nodes_dn=[\"CN=node-1,OU=LBL,O=LBNL,L=Berkeley,ST=California,C=US\"]"
      - "plugins.security.audit.type=internal_opensearch"
      # Other existing environment variables
      - "bootstrap.memory_lock=true"
      - "discovery.type=single-node"
    volumes:
      - ./docker/opensearch/certificates:/usr/share/opensearch/config/certificates
    networks:
      - internal-net
    # IMPORTANT: Remove any port mappings to ensure OpenSearch is only accessible internally
    # ports:
    #  - "9200:9200"
    #  - "9600:9600"
```

## Step 2: Update OpenSearch Dashboards Configuration

Update `docker-services.yml` for OpenSearch Dashboards:

```yaml
services:
  opensearch-dashboards:
    image: opensearchproject/opensearch-dashboards:2.17.1
    restart: "unless-stopped"
    environment:
      - "DISABLE_SECURITY_DASHBOARDS_PLUGIN=false"
      - "OPENSEARCH_HOSTS=https://search:9200"
      - "OPENSEARCH_SSL_VERIFICATIONMODE=none"
      - "OPENSEARCH_USERNAME=${OPENSEARCH_ADMIN_USER}"
      - "OPENSEARCH_PASSWORD=${OPENSEARCH_ADMIN_PASSWORD}"
    volumes:
      - ./docker/opensearch-dashboards/config/opensearch_dashboards.yml:/usr/share/opensearch-dashboards/config/opensearch_dashboards.yml
    networks:
      - internal-net
    # Keep port mapping for dashboard if admin access is needed, otherwise comment out
    # ports:
    #  - "5601:5601"
```

## Step 3: Create Environment Variables for Credentials

Create a `.env` file in your project root (and add to .gitignore):

```
# OpenSearch security credentials
OPENSEARCH_ADMIN_USER=admin_strong_user
OPENSEARCH_ADMIN_PASSWORD=complex_password_with_special_chars_and_numbers_123!@#
```

## Step 4: Create SSL Certificates

Create required directories and generate production-ready certificates:

```bash
# Create directories
mkdir -p docker/opensearch/certificates
mkdir -p docker/opensearch-dashboards/config

# Navigate to certificates directory
cd docker/opensearch/certificates

# Generate CA with stronger key
openssl genrsa -out root-ca-key.pem 4096
openssl req -new -x509 -sha256 -key root-ca-key.pem -out root-ca.pem -days 3650 \
  -subj "/C=US/ST=California/L=Berkeley/O=LBNL/OU=LBL/CN=LBL-OpenSearch-CA"

# Generate node certificate with stronger key
openssl genrsa -out node-key.pem 4096
openssl req -new -key node-key.pem -out node.csr \
  -subj "/C=US/ST=California/L=Berkeley/O=LBNL/OU=LBL/CN=node-1"
  
# Add SAN extensions
cat > node.ext << EOF
subjectAltName = DNS:search, DNS:localhost, IP:127.0.0.1
EOF

# Sign with the CA, including SAN extensions
openssl x509 -req -in node.csr -CA root-ca.pem -CAkey root-ca-key.pem \
  -CAcreateserial -sha256 -out node.pem -days 3650 -extfile node.ext

# Generate admin certificate with stronger key
openssl genrsa -out admin-key.pem 4096
openssl req -new -key admin-key.pem -out admin.csr \
  -subj "/C=US/ST=California/L=Berkeley/O=LBNL/OU=LBL/CN=admin"
openssl x509 -req -in admin.csr -CA root-ca.pem -CAkey root-ca-key.pem \
  -CAcreateserial -sha256 -out admin.pem -days 3650

# Set proper permissions
chmod 600 *.key.pem *.pem
```

## Step 5: Create Configuration Files

Create OpenSearch Dashboards configuration file with enhanced security:

```bash
cat > docker/opensearch-dashboards/config/opensearch_dashboards.yml << EOF
server.name: opensearch-dashboards
server.host: "0.0.0.0"
opensearch.hosts: ["https://search:9200"]
opensearch.ssl.verificationMode: certificate
opensearch.ssl.certificateAuthorities: ["/usr/share/opensearch-dashboards/config/certificates/root-ca.pem"]
opensearch.username: "${OPENSEARCH_ADMIN_USER}"
opensearch.password: "${OPENSEARCH_ADMIN_PASSWORD}"
opensearch.requestHeadersWhitelist: ["securitytenant", "Authorization"]
opensearch_security.multitenancy.enabled: true
opensearch_security.readonly_mode.roles: ["kibana_read_only"]
server.ssl.enabled: true
server.ssl.certificate: "/usr/share/opensearch-dashboards/config/certificates/node.pem"
server.ssl.key: "/usr/share/opensearch-dashboards/config/certificates/node-key.pem"
EOF

# Update volumes in docker-services.yml to mount CA cert for dashboards
# Add this to the opensearch-dashboards volumes section:
# - ./docker/opensearch/certificates/root-ca.pem:/usr/share/opensearch-dashboards/config/certificates/root-ca.pem
# - ./docker/opensearch/certificates/node.pem:/usr/share/opensearch-dashboards/config/certificates/node.pem
# - ./docker/opensearch/certificates/node-key.pem:/usr/share/opensearch-dashboards/config/certificates/node-key.pem
```

## Step 6: Update InvenioRDM Configuration

Update InvenioRDM application configuration in your `invenio.cfg` file to use the internal Docker network:

```python
SEARCH_CLIENT_CONFIG = {
    "hosts": ["https://search:9200"],  # Use the Docker service name
    "http_auth": (
        os.environ.get("OPENSEARCH_ADMIN_USER", "admin_strong_user"),
        os.environ.get("OPENSEARCH_ADMIN_PASSWORD", "complex_password_with_special_chars_and_numbers_123!@#")
    ),
    "use_ssl": True,
    "verify_certs": True,
    "ca_certs": "/path/to/certificates/root-ca.pem",  # Update with actual path
}
```

## Step 7: Docker Networking Configuration

Ensure your `docker-compose.yml` properly defines the network configuration:

```yaml
version: '2.2'
networks:
  internal-net:
    driver: bridge
    # Make this an internal network that cannot connect to the outside world
    internal: true
    # Additional security options
    driver_opts:
      com.docker.network.bridge.name: "invenio-internal"
      # Additional security options if needed

services:
  # All services should use this network
  search:
    networks:
      - internal-net
  opensearch-dashboards:
    networks:
      - internal-net
  # Other services...
```

## Step 8: Implement Periodic Certificate Rotation

Add a reminder to your system maintenance schedule:

```
# Certificate Rotation Plan
- Regenerate all certificates annually
- Update certificate paths in configuration
- Restart services after certificate updates
- Document the rotation process and schedule
- Set automated reminders for certificate expiration
```

## Step 9: Implementation Steps

1. Create a backup of your current data:
   ```bash
   # Backup any important indices
   curl -XGET "http://localhost:9200/_cat/indices" > indices_backup.txt
   # For each important index:
   curl -XGET "http://localhost:9200/important_index/_search?size=10000" > important_index_backup.json
   ```

2. Stop all containers:
   ```bash
   docker-compose down
   ```

3. Implement all configuration changes described above

4. Start containers with new configuration:
   ```bash
   docker-compose up -d
   ```

5. Verify the application works correctly with the secure configuration

## Security Considerations

- OpenSearch is now only accessible from within the Docker network
- Strong password policies are implemented
- Certificates use 4096-bit keys for enhanced security
- Certificates are valid for 10 years (3650 days) but should be rotated annually
- Environment variables are used for sensitive credentials
- All certificate files have restricted permissions
- Proper Subject Alternative Names (SANs) are configured for certificates
- Internal network configuration prevents external access to OpenSearch
