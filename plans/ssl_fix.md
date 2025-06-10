## Plan for SSL Certificate Location Update

After moving the SSL certificates from `./docker/ssl/` to `~/.config/lbnl-data-repository/ssl/`, I need to identify all files that reference the old certificate paths and update them accordingly.

## Questions to Consider

Before providing specific edit instructions, I need to understand:

1. **Docker Compose Configuration**: Do you have existing `docker-compose.yml` and `docker-services.yml` files that mount the SSL directory?

2. **InvenioRDM Configuration**: Do you have an existing `invenio.cfg` file with SSL certificate paths?

3. **Nginx Configuration**: Do you have the `./docker/nginx/nginx.conf` file mentioned in the security plan?

4. **Environment Setup**: Do you have environment setup scripts that reference certificate paths?

5. **Docker Volume Mounts**: How should Docker containers access the certificates in the user's home directory? Should we:
   - Mount `~/.config/lbnl-data-repository/ssl` directly into containers?
   - Copy certificates to a temporary location during build?
   - Use symbolic links?

## Files That Likely Need Updates

Based on the security plan, these files probably need certificate path updates:

### 1. Docker Compose Files
- `docker-compose.yml` - Volume mounts for SSL certificates
- `docker-services.yml` - OpenSearch and OpenSearch Dashboards SSL configuration

### 2. InvenioRDM Configuration
- `invenio.cfg` - CA certificate path in `SEARCH_CLIENT_CONFIG`

### 3. Documentation/Scripts
- Any setup or deployment scripts
- README files with certificate instructions

### 4. Potential Issues to Address
- **Docker volume mounting**: `~/.config/lbnl-data-repository/ssl` needs to be accessible to containers
- **File permissions**: Containers may need specific user/group permissions
- **Path resolution**: `$HOME` variable expansion in Docker contexts

## Recommended Approach

I suggest a hybrid approach:
1. Generate certificates in `~/.config/lbnl-data-repository/ssl/` (secure storage)
2. Create symbolic links or copy certificates to `./docker/ssl/` for Docker access
3. Update all configuration files to reference the appropriate paths

