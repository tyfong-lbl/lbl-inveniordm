# Project Blueprint: Enhancing run_invenio.sh with Stop/Start/Restart Functionality

## Overview
Based on the `stop_start.md` plan, we need to enhance the existing `run_invenio.sh` script with new command-line flags for process management, fix file storage location, and improve overall robustness.

## Analysis of Current State
The current `run_invenio.sh` script is already quite sophisticated with:
- Docker Compose service management
- SSL certificate handling
- Health checking for all services
- InvenioRDM initialization and startup
- Environment variable loading
- Comprehensive logging and status reporting

## Detailed Blueprint

### Phase 1: Core Infrastructure Enhancement
1. **Process Management Foundation**
   - Improve PID file handling
   - Add process status checking utilities
   - Create cleanup functions

2. **Command Line Interface Extension**
   - Add new flags: `--stop`, `--stop-all`, `--restart`, `--status`
   - Enhance argument parsing
   - Update help documentation

### Phase 2: Stop/Start Functionality
3. **Stop Functions Implementation**
   - InvenioRDM process stopping
   - Container stopping with volume preservation
   - Graceful shutdown procedures

4. **Status Reporting Enhancement**
   - Detailed process status
   - Container health reporting
   - Service connectivity checks

### Phase 3: Configuration and Storage Fixes
5. **File Storage Location Fix**
   - Change from `/tmp/data` to `./instance/files/`
   - Make configurable via environment
   - Update initialization commands

6. **Repository Management**
   - Add `.gitignore` entries
   - Ensure proper file permissions

### Phase 4: Integration and Testing
7. **Restart Functionality**
   - Combine stop and start operations
   - Preserve user preferences
   - Handle edge cases

8. **Final Integration**
   - Comprehensive testing
   - Documentation updates
   - Error handling improvements

## Step-by-Step Implementation Plan

### Step 1: Process Management Utilities
- Add utility functions for PID management
- Implement process status checking
- Create cleanup functions

### Step 2: Enhanced Argument Parsing
- Extend command line argument handling
- Add new flag definitions
- Update help documentation

### Step 3: Stop InvenioRDM Process Function
- Implement `--stop` functionality
- Handle graceful process termination
- Clean up PID files and logs

### Step 4: Stop All Services Function
- Implement `--stop-all` functionality
- Stop containers while preserving volumes
- Maintain data integrity

### Step 5: Enhanced Status Reporting
- Implement `--status` functionality
- Show detailed service information
- Report process and container states

### Step 6: File Storage Configuration Fix
- Update file storage location logic
- Make storage location configurable
- Update initialization commands

### Step 7: Repository Management
- Create/update `.gitignore`
- Handle instance directory creation
- Set proper permissions

### Step 8: Restart Functionality
- Implement `--restart` functionality
- Coordinate stop and start operations
- Preserve user arguments

### Step 9: Integration and Polish
- Integrate all new functions
- Add comprehensive error handling
- Update documentation and help text

---

# Implementation Prompts

## Prompt 1: Process Management Utilities

```
/edit run_invenio.sh

Add utility functions for better process management. Add these functions after the existing functions but before the argument parsing section:

1. Add a function `get_invenio_pid()` that:
   - Checks if invenio.pid file exists
   - Validates the PID empty string if not running
is still running
   - Returns the PID or 
2. Add a function `is_invenio_running()` that:
   - Uses get_invenio_pid to check if InvenioRDM is running
   - Returns 0 (true) if running, 1 (false) if not

3. Add a function `cleanup_invenio_files()` that:
   - Removes invenio.pid file if it exists
   - Optionally removes invenio.log file if passed --clean-logs flag
   - Creates a backup of logs before removal

4. Add a function `show_process_status()` that:
   - Shows InvenioRDM process status
   - Shows container status summary
   - Shows port usage for key services

Place these functions in a clearly marked "# Process Management Utilities" section.
```

## Prompt 2: Enhanced Argument Parsing

```
/edit run_invenio.sh

Extend the command line argument parsing to support the new flags. Update the argument parsing section:

1. Add new variables at the top with existing defaults:
   - STOP_MODE=false
   - STOP_ALL_MODE=false  
   - RESTART_MODE=false
   - STATUS_MODE=false

2. Add new cases in the argument parsing while loop:
   - --stop: sets STOP_MODE=true
   - --stop-all: sets STOP_ALL_MODE=true
   - --restart: sets RESTART_MODE=true  
   - --status: sets STATUS_MODE=true

3. Update the --help section to document all new flags:
   - --stop: Stop InvenioRDM process only (containers keep running)
   - --stop-all: Stop InvenioRDM process + all containers (preserve data/volumes)
   - --restart: Stop everything, then restart with same options
   - --status: Show detailed status of InvenioRDM process and all containers

4. Add validation that only one primary mode can be selected at a time (stop, stop-all, restart, status, or the existing modes).

5. Update the mode announcement section to handle the new modes.
```

## Prompt 3: Stop InvenioRDM Process Function

```
/edit run_invenio.sh

Add a function to stop the InvenioRDM process gracefully. Add this function in the "Process Management Utilities" section:

1. Create a function `stop_invenio_process()` that:
   - Checks if InvenioRDM is running using the existing utilities
   - If running, attempts graceful shutdown with SIGTERM
   - Waits up to 30 seconds for graceful shutdown
   - Uses SIGKILL if graceful shutdown fails
   - Cleans up PID file and shows status
   - Returns 0 on success, 1 on failure

2. The function should:
   - Print clear status messages about what it's doing
   - Show the PID being stopped
   - Indicate success/failure clearly
   - Handle the case where no process is running
   - Optionally clean up log files if a flag is passed

3. Include proper error handling for cases where:
   - PID file exists but process is already dead
   - Process doesn't respond to signals
   - Permission issues occur

Make sure to use the existing echo styling patterns for consistency.
```

## Prompt 4: Stop All Services Function

```
/edit run_invenio.sh

Add a function to stop all services while preserving data. Add this function in the "Process Management Utilities" section:

1. Create a function `stop_all_services()` that:
   - First stops the InvenioRDM process using stop_invenio_process()
   - Then stops all Docker containers using docker-compose down (without -v flag to preserve volumes)
   - Shows clear progress messages
   - Confirms all containers are stopped
   - Lists what data/volumes are preserved

2. The function should:
   - Use the existing environment loading pattern: `env $(cat ~/.config/lbnl-data-repository/.env | grep -v '^#' | sed 's/[[:space:]]*$//' | xargs)`
   - Run: `docker-compose -f docker-compose.yml down --remove-orphans`
   - NOT use the -v flag to preserve volumes and data
   - Show which volumes/data are being preserved
   - Provide clear success/failure messages

3. Include verification that:
   - All containers are actually stopped
   - Volumes are still present
   - No orphaned containers remain

4. Use the existing echo styling and formatting patterns for consistency.
```

## Prompt 5: Enhanced Status Reporting Function

```
/edit run_invenio.sh

Create a comprehensive status reporting function. Add this function in the "Process Management Utilities" section:

1. Create a function `show_detailed_status()` that provides a complete system status report:

   **InvenioRDM Process Status:**
   - Check if InvenioRDM is running (use existing utilities)
   - Show PID, port, uptime if running
   - Show log file size and recent errors if any

   **Container Status:**
   - Use existing service status checking logic
   - Show running/stopped status for each service
   - Show container health and restart count
   - Show port mappings for each service

   **Resource Usage:**
   - Show which ports are in use
   - Basic disk usage for volumes
   - Show recent container logs (last 3 lines) for any failed services

   **Quick Access URLs:**
   - List all service URLs (like existing success messages)
   - Only show URLs for running services

2. The function should:
   - Use existing service checking patterns from check_services_ready()
   - Format output clearly with sections and consistent styling
   - Handle cases where no services are running
   - Show helpful next steps based on current state

3. Make this the main handler for STATUS_MODE=true
```

## Prompt 6: File Storage Configuration Fix

```
/edit run_invenio.sh

Fix the file storage location issue by updating the initialization logic:

1. In the `initialize_invenio()` function, update the file location command:
   - Change from: `"invenio files location create --default 'default-location' /tmp/data"`
   - To use a configurable location with default: `./instance/files/`

2. Add logic before the initialization commands to:
   - Check for INVENIO_FILES_LOCATION environment variable
   - Default to "./instance/files/" if not set
   - Create the directory if it doesn't exist
   - Set proper permissions

3. Add a new variable at the top of the script:
   ```bash
   FILES_LOCATION="${INVENIO_FILES_LOCATION:-./instance/files/}"
   ```

4. Update the command in the commands array to use the variable:
   "invenio files location create --default 'default-location' '$FILES_LOCATION'"
   ```

5. Add directory creation logic in initialize_invenio():
   - Create the directory if it doesn't exist
   - Show a message about where files will be stored
   - Ensure proper permissions are set

Make sure the path handling works correctly for both relative and absolute paths.
```

## Prompt 7: Repository Management - .gitignore

```
/edit .gitignore

Edit the .gitignore file for the project to handle InvenioRDM-specific files and directories:

1. Ensure there is a comprehensive .gitignore file that includes:

   **InvenioRDM Instance Files:**
   - instance/
   - static/
   - assets/

   **Runtime Files:**
   - *.pid
   - *.log
   - invenio.log
   - celery*.log

   **SSL and Config:**
   - .env
   - ssl/
   - certificates/

   **Python/Development:**
   - __pycache__/
   - *.pyc
   - *.pyo
   - .pytest_cache/
   - .coverage
   - venv/
   - .venv/

   **Docker/System:**
   - .docker/
   - docker-compose.override.yml

   **Editor/IDE:**
   - .vscode/
   - .idea/
   - *.swp
   - *.swo
   - *~
   - .DS_Store
   - Thumbs.db

2. Add comments explaining each section

3. Include a header comment explaining this is for the LBNL Data Repository InvenioRDM project

Make sure to include all the key files that should not be committed to version control.
```

## Prompt 8: Restart Functionality Implementation

```
/edit run_invenio.sh

Implement the restart functionality that coordinates stopping and starting services:

1. Create a function `restart_services()` that:
   - Preserves the original command line arguments (except --restart)
   - First calls stop_all_services() to stop everything
   - Waits a few seconds for clean shutdown
   - Then reconstructs the startup command with preserved arguments
   - Calls the appropriate startup functions

2. The function should:
   - Store original arguments in an array at the beginning of the script
   - Filter out --restart from the arguments to avoid infinite loop
   - Handle all combinations (e.g., --restart --invenio --port 8080 --debug)
   - Show clear messages about what's being restarted
   - Handle errors gracefully if restart fails

3. Add logic to store original arguments near the top of the script:
   ```bash
   # Store original arguments for restart functionality
   ORIGINAL_ARGS=("$@")
   ```

4. Add the restart logic in the main execution flow:
   - Check for RESTART_MODE=true
   - Call restart_services() if true
   - Exit after restart completes

5. The restart should preserve all user preferences:
   - Port numbers
   - Debug mode
   - InvenioRDM startup flag
   - Any other flags that were set

Make sure the restart maintains the same behavior as the original command would have.
```

## Prompt 9: Integration and Main Flow Logic

```
/edit run_invenio.sh

Integrate all the new functionality into the main script flow and add proper mode handling:

1. Add the main mode execution logic after the argument parsing and before the existing startup logic:

   ```bash
   # Handle the new modes before existing startup logic
   if [ "$STATUS_MODE" = true ]; then
       show_detailed_status
       exit 0
   elif [ "$STOP_MODE" = true ]; then
       stop_invenio_process
       exit $?
   elif [ "$STOP_ALL_MODE" = true ]; then
       stop_all_services
       exit $?
   elif [ "$RESTART_MODE" = true ]; then
       restart_services
       exit $?
   fi
   ```

2. Update the mode validation to prevent conflicting modes:
   - Add validation that only one primary mode is selected
   - Show error message for conflicting flags
   - Update help text to clarify mode exclusivity

3. Add error handling throughout:
   - Wrap function calls in proper error checking
   - Provide meaningful error messages
   - Ensure proper exit codes are returned

4. Update the final success messages to be aware of the mode:
   - Show different messages based on whether this was a fresh start or restart
   - Include the new management commands in the help text
   - Add the new stop commands to the management section

5. Ensure backward compatibility:
   - All existing functionality should work exactly as before
   - Default behavior (no flags) should remain unchanged
   - Existing flag combinations should continue to work

Test that all modes work correctly and don't interfere with existing functionality.
```
