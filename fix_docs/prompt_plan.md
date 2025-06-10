# Step-by-Step Blueprint for Fix Startup Script Implementation

## Phase 1: Core Infrastructure Setup
### Step 1: Argument Parsing Framework
**Goal:** Implement command-line argument parsing for `--debug` and `--port` flags.

**Prompt 1:**
```text
Implement a bash script argument parser that supports:
- --debug flag (sets DEBUG_MODE=true)
- --port <port> option with validation (requires numeric port between 1024-65535)
- --help option with usage instructions
- Error handling for invalid options/missing port value
Use functions for clean structure and return error codes
```

### Step 2: Error Handling Framework
**Goal:** Create a robust error handling system with cleanup on failure.

**Prompt 2:**
```text
Add error handling framework to the script:
- Implement cleanup_on_error() function that:
  - Detects script failure via $?
  - Outputs troubleshooting tips
  - Preserves invenio.log if exists
- Set trap for EXIT signal
- Add set -e and set -o pipefail
```

### Step 3: Validation Functions
**Goal:** Implement environment and certificate validation checks.

**Prompt 3:**
```text
Create validation functions:
1. validate_environment():
   - Check existence/readability of ~/.config/lbnl-data-repository/.env
   - Verify OPENSEARCH_ADMIN_PASSWORD presence in .env
2. validate_ssl_certificates():
   - Check existence of server.pem, server-key.pem, and ca.pem in $HOME/.config/lbnl-data-repository/ssl
   - Validate file permissions
```

## Phase 2: Service Management
### Step 4: Docker Composition Control
**Goal:** Implement Docker Compose control functions.

**Prompt 4:**
```text
Implement Docker management functions:
1. build_images() function with:
   - docker-compose build with progress display
   - Environment variable injection from .env
2. start_services() function with:
   - docker-compose up -d --remove-orphans
   - Environment variable injection
```

### Step 5: Service Health Checks
**Goal:** Create service readiness verification functions.

**Prompt 5:**
```text
Develop service check functions:
1. check_services_ready() that verifies:
   - All services are running (db, search, etc)
   - Proper restart counts
   - Specific health checks (pg_isready, curl tests, etc)
2. Implement exponential backoff with 5-minute timeout
```

### Step 6: Connectivity Tests
**Goal:** Implement backend connectivity verification.

**Prompt 6:**
```text
Create backend connectivity tests:
1. check_invenio_backend_connectivity() that verifies:
   - OpenSearch access via curl with auth
   - PostgreSQL connectivity via pg_isready
   - Redis ping response
   - RabbitMQ diagnostics ping
```

## Phase 3: Logging and Output
### Step 7: Structured Logging
**Goal:** Implement prefixed logging functions.

**Prompt 7:**
```text
Add logging functions with service prefixes:
- Create log_with_prefix() helper function
- Implement specialized loggers for each service (log_search, log_db, etc)
- Use consistent formatting for all log outputs
```

### Step 8: Success Summary
**Goal:** Create user-friendly startup completion report.

**Prompt 8:**
```text
Develop display_success_summary() function that outputs:
- Formatted service URLs with colors
- Credentials table
- Management commands list
- Use consistent styling and spacing
- Include port number parameter
```

## Phase 4: Integration and Polishing
### Step 9: Full Execution Flow
**Goal:** Wire all components into main execution flow.

**Prompt 9:**
```text
Implement main execution flow that:
1. Runs pre-flight validations
2. Starts Docker services
3. Performs health checks
4. Starts InvenioRDM (non-debug mode)
5. Runs connectivity tests
6. Displays success summary
Use proper conditional logic and error propagation
```

### Step 10: Final Enhancements
**Goal:** Add finishing touches and polishing.

**Prompt 10:**
```text
Implement final enhancements:
1. Add debug mode functionality that skips Invenio startup
2. Improve error messages with service-specific details
3. Add progress indicators during waits
4. Format all outputs consistently with emojis and separators
5. Add final cleanup and validation checks
```

---

### Implementation Strategy
1. **Modular Development:** Build each component in isolation first (e.g., argument parsing without Docker commands)
2. **Incremental Testing:** After each step, test failure scenarios to ensure error handling works
3. **Stubbing:** Create dummy functions for later components during early development
4. **Progressive Integration:** Combine components gradually, starting with validation → Docker control → health checks
5. **Stub Environment:** Create minimal .env and certificate files for testing purposes