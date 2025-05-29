## Plan: Fix OpenSearch and Nginx Configuration Issues

### Overview
This plan addresses two critical issues:
1. OpenSearch failing to start due to incorrect SSL certificate paths
2. Nginx configuration using deprecated http2 directive

### Prerequisites
- Ensure SSL certificates exist in `~/.config/lbnl-data-repository/ssl/`
  - `server.pem`
  - `server-key.pem`
  - `ca.pem`

### File Modifications

#### 1. Create/Update Environment File: `~/.config/lbnl-data-repository/.env`

**Instructions:**
1. Create the file if it doesn't exist
2. Add the following lines:
```bash
OPENSEARCH_ADMIN_PASSWORD=YourSecurePassword123!
OPENSEARCH_ADMIN_USER=admin
```

#### 2. Fix OpenSearch Certificate Paths: `docker-services.yml`

**Line-by-line instructions:**

3. **Line 84:** Change `- "plugins.security.ssl.http.pemcert_filepath=config/certificates/server.pem"` to:
   ```yaml
   - "plugins.security.ssl.http.pemcert_filepath=/usr/share/opensearch/config/certificates/server.pem"
   ```

4. **Line 85:** Change `- "plugins.security.ssl.http.pemkey_filepath=config/certificates/server-key.pem"` to:
   ```yaml
   - "plugins.security.ssl.http.pemkey_filepath=/usr/share/opensearch/config/certificates/server-key.pem"
   ```

5. **Line 86:** Change `- "plugins.security.ssl.http.pemtrustedcas_filepath=config/certificates/ca.pem"` to:
   ```yaml
   - "plugins.security.ssl.http.pemtrustedcas_filepath=/usr/share/opensearch/config/certificates/ca.pem"
   ```

6. **Line 87:** Change `- "plugins.security.ssl.transport.pemcert_filepath=config/certificates/server.pem"` to:
   ```yaml
   - "plugins.security.ssl.transport.pemcert_filepath=/usr/share/opensearch/config/certificates/server.pem"
   ```

7. **Line 88:** Change `- "plugins.security.ssl.transport.pemkey_filepath=config/certificates/server-key.pem"` to:
   ```yaml
   - "plugins.security.ssl.transport.pemkey_filepath=/usr/share/opensearch/config/certificates/server-key.pem"
   ```

8. **Line 89:** Change `- "plugins.security.ssl.transport.pemtrustedcas_filepath=config/certificates/ca.pem"` to:
   ```yaml
   - "plugins.security.ssl.transport.pemtrustedcas_filepath=/usr/share/opensearch/config/certificates/ca.pem"
   ```

#### 3. Fix Nginx Configuration: `docker/nginx/nginx.conf`

**Line-by-line instructions:**

9. **Line 6:** Change `listen 443 ssl http2;` to:
   ```nginx
   listen 443 ssl;
   ```

10. **Line 7:** After the previous line, add a new line:
    ```nginx
    http2 on;
    ```

#### 4. Remove Conflicting Configuration: `docker/nginx/conf.d/default.conf`

**Instructions:**

11. **Delete the entire file** `docker/nginx/conf.d/default.conf` to prevent configuration conflicts

### Execution Steps

After making all the above changes:

1. Stop all running containers:
   ```bash
   docker-compose down
   ```

2. Rebuild the Docker images to ensure changes are applied:
   ```bash
   docker-compose build
   ```

3. Run the service startup script:
   ```bash
   ./run_service_containers.sh
   ```

### Verification

The `run_service_containers.sh` script will automatically verify:
- All SSL certificates are present
- OpenSearch starts successfully and responds to HTTPS requests
- Nginx frontend is accessible via HTTPS
- All other services (PostgreSQL, Redis, RabbitMQ) are healthy

### Troubleshooting

If services fail to start after these changes:

1. Check the logs for specific services:
   ```bash
   docker-compose logs search    # For OpenSearch issues
   docker-compose logs frontend  # For Nginx issues
   ```

2. Verify SSL certificates are readable:
   ```bash
   ls -la ~/.config/lbnl-data-repository/ssl/
   ```

3. Ensure the `.env` file is properly loaded:
   ```bash
   cat ~/.config/lbnl-data-repository/.env
   ```

### Expected Outcome

After implementing these changes:
- OpenSearch will successfully find and load SSL certificates
- Nginx will start without deprecation warnings
- All services will pass health checks in the startup script
- The InvenioRDM instance will be accessible via HTTPS at `https://localhost:5001`

