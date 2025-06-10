## Detailed Bug Fix Specification

### **Problem Summary:**
The frontend container keeps restarting due to nginx configuration errors. The configuration is trying to connect to non-existent upstream servers and using incorrect SSL certificate paths.

### **Root Causes:**
1. **Invalid upstream servers**: `default.conf` references `web-ui:5000` and `web-api:5000` which don't exist in the docker-compose setup
2. **Wrong SSL certificate paths**: Configuration uses `test.crt`/`test.key` instead of the mounted `server.pem`/`server-key.pem`
3. **Incorrect proxy method**: Using `uwsgi_pass` instead of `proxy_pass` for HTTP communication
4. **Syntax errors**: Extra backslashes in `nginx.conf` file

### **Files to Modify:**

#### **File 1: `/docker/nginx/conf.d/default.conf`**

**Changes needed:**
1. **Lines 8-12**: Replace upstream server definitions:
   ```nginx
   # BEFORE:
   upstream ui_server {
     server web-ui:5000 fail_timeout=0;
   }
   upstream api_server {
     server web-api:5000 fail_timeout=0;
   }
   
   # AFTER:
   upstream invenio_server {
     server host.docker.internal:5000 fail_timeout=0;
   }
   ```

2. **Lines 34-35**: Update SSL certificate paths:
   ```nginx
   # BEFORE:
   ssl_certificate /etc/ssl/certs/test.crt;
   ssl_certificate_key /etc/ssl/private/test.key;
   
   # AFTER:
   ssl_certificate /etc/ssl/certs/server.pem;
   ssl_certificate_key /etc/ssl/private/server-key.pem;
   ```

3. **Lines 63-75**: Replace UI server location block:
   ```nginx
   # BEFORE:
   location / {
     uwsgi_pass ui_server;
     include uwsgi_params;
     uwsgi_buffering off;
     uwsgi_request_buffering off;
     chunked_transfer_encoding off;
     uwsgi_param Host $host;
     uwsgi_param X-Forwarded-For $proxy_add_x_forwarded_for;
     uwsgi_param X-Forwarded-Proto $scheme;
     uwsgi_param X-Request-ID $request_id;
     uwsgi_hide_header X-Session-ID;
     uwsgi_hide_header X-User-ID;
     client_max_body_size 100m;
   }
   
   # AFTER:
   location / {
     proxy_pass http://invenio_server;
     proxy_set_header Host $host;
     proxy_set_header X-Real-IP $remote_addr;
     proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
     proxy_set_header X-Forwarded-Proto $scheme;
     proxy_set_header X-Request-ID $request_id;
     proxy_redirect off;
     client_max_body_size 100m;
   }
   ```

4. **Lines 76-88**: Replace API server location block:
   ```nginx
   # BEFORE:
   location /api {
     uwsgi_pass api_server;
     include uwsgi_params;
     uwsgi_buffering off;
     uwsgi_request_buffering off;
     chunked_transfer_encoding off;
     uwsgi_param Host $host;
     uwsgi_param X-Forwarded-For $proxy_add_x_forwarded_for;
     uwsgi_param X-Forwarded-Proto $scheme;
     uwsgi_param X-Request-ID $request_id;
     uwsgi_hide_header X-Session-ID;
     uwsgi_hide_header X-User-ID;
     client_max_body_size 100m;
   }
   
   # AFTER:
   location /api {
     proxy_pass http://invenio_server;
     proxy_set_header Host $host;
     proxy_set_header X-Real-IP $remote_addr;
     proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
     proxy_set_header X-Forwarded-Proto $scheme;
     proxy_set_header X-Request-ID $request_id;
     proxy_redirect off;
     client_max_body_size 100m;
   }
   ```

5. **Lines 93-108**: Replace API files location block:
   ```nginx
   # BEFORE:
   location ~ /api/records/.+/draft/files/.+/content {
     gzip off;
     uwsgi_pass api_server;
     include uwsgi_params;
     uwsgi_buffering off;
     uwsgi_request_buffering off;
     chunked_transfer_encoding off;
     uwsgi_param Host $host;
     uwsgi_param X-Forwarded-For $proxy_add_x_forwarded_for;
     uwsgi_param X-Forwarded-Proto $scheme;
     uwsgi_param X-Request-ID $request_id;
     uwsgi_hide_header X-Session-ID;
     uwsgi_hide_header X-User-ID;
     client_max_body_size 50G;
   }
   
   # AFTER:
   location ~ /api/records/.+/draft/files/.+/content {
     gzip off;
     proxy_pass http://invenio_server;
     proxy_set_header Host $host;
     proxy_set_header X-Real-IP $remote_addr;
     proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
     proxy_set_header X-Forwarded-Proto $scheme;
     proxy_set_header X-Request-ID $request_id;
     proxy_redirect off;
     client_max_body_size 50G;
   }
   ```

#### **File 2: `/docker/nginx/nginx.conf`**

**Changes needed:**
1. **Line 38**: Remove backslash from proxy_pass:
   ```nginx
   # BEFORE:
   proxy_pass http://backend\;
   
   # AFTER:
   proxy_pass http://backend;
   ```

2. **Last line**: Remove backslash from return statement:
   ```nginx
   # BEFORE:
   return 301 https://$server_name$request_uri\;
   
   # AFTER:
   return 301 https://$server_name$request_uri;
   ```

### **Testing Steps:**
1. Apply the configuration changes
2. Rebuild the frontend container: `docker-compose build frontend`
3. Start containers: `docker-compose up -d`
4. Verify frontend container stays running: `docker-compose ps`
5. Check nginx logs: `docker-compose logs frontend`
6. Test HTTP to HTTPS redirect: `curl -I http://localhost:5000`
7. Test HTTPS access: `curl -k -I https://localhost:5000`

### **Expected Outcome:**
- Frontend container should start and remain running without restarts
- Nginx should successfully proxy requests to the InvenioRDM application running on the host
- SSL certificates should be properly loaded
- HTTP requests should redirect to HTTPS
