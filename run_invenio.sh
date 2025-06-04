#!/bin/bash

# Store original arguments for restart functionality
ORIGINAL_ARGS=("$@")

FILES_LOCATION="${INVENIO_FILES_LOCATION:-./instance/files/}"

# Default values
DEBUG_MODE=false
START_INVENIO=false
INVENIO_PORT=5002
RESET_MODE=false
STOP_MODE=false
STOP_ALL_MODE=false
RESTART_MODE=false
STATUS_MODE=false

# Function to perform reset and initialization
perform_reset_and_init() {
    echo "🗑️  RESET MODE: This will delete all existing data"
    echo ""
    echo "Will delete:"
    echo "   • All Docker volumes (database data, search indices, etc.)"
    echo "   • All container data"
    echo "   • All InvenioRDM application data"
    echo ""
    echo -n "Continue? (y/N): "
    read -r response
    
    if [[ ! "$response" =~ ^[Yy]$ ]]; then
        echo "Reset cancelled."
        exit 0
    fi
    
    echo ""
    echo "🧹 Stopping containers and removing volumes..."
    
    # Stop all containers and remove volumes
    env $(cat ~/.config/lbnl-data-repository/.env | grep -v '^#' | sed 's/[[:space:]]*$//' | xargs) docker-compose -f docker-compose.yml down -v
    
    # Remove orphaned volumes
    echo "Removing orphaned volumes..."
    docker volume prune -f
    
    echo "✅ Cleanup completed"
    echo ""
    
    return 0
}

# Function to start InvenioRDM with proper environment
start_invenio_rdm() {
    local port=${1:-5002}
    echo "🚀 Starting InvenioRDM with HTTPS on port $port..."
    
    # Check if port is available
    if lsof -i ":$port" >/dev/null 2>&1; then
        echo "❌ ERROR: Port $port is already in use"
        echo "Please choose a different port or stop the service using that port."
        return 1
    fi
    
    # Check if SSL certificates exist
    local cert_path="${HOME}/.config/lbnl-data-repository/ssl/server.pem"
    local key_path="${HOME}/.config/lbnl-data-repository/ssl/server-key.pem"
    
    if [ ! -f "$cert_path" ]; then
        echo "❌ ERROR: SSL certificate not found at $cert_path"
        return 1
    fi
    
    if [ ! -f "$key_path" ]; then
        echo "❌ ERROR: SSL private key not found at $key_path"
        return 1
    fi
    
    # Start InvenioRDM with HTTPS and environment variables loaded
    echo "Loading environment and starting InvenioRDM with SSL..."
    env $(cat ~/.config/lbnl-data-repository/.env | grep -v '^#' | sed 's/[[:space:]]*$//' | xargs) \
        nohup invenio run --host 127.0.0.1 --port "$port" \
        --cert "$cert_path" --key "$key_path" > invenio.log 2>&1 &
    
    local invenio_pid=$!
    echo "$invenio_pid" > invenio.pid
    echo "InvenioRDM started with HTTPS and PID: $invenio_pid"
    
    # Wait for InvenioRDM to start up
    echo "Waiting for InvenioRDM to initialize..."
    local timeout=120
    local elapsed=0
    local interval=3
    
    while [ $elapsed -lt $timeout ]; do
        if kill -0 "$invenio_pid" 2>/dev/null; then
            # Check HTTPS endpoint with certificate verification disabled for self-signed certs
            if curl -k -s -f "https://127.0.0.1:$port" >/dev/null 2>&1; then
                echo "✅ InvenioRDM is responding on HTTPS at port $port"
                return 0
            fi
        else
            echo "❌ ERROR: InvenioRDM process died during startup"
            echo "Check invenio.log for error details:"
            tail -20 invenio.log
            return 1
        fi
        
        sleep $interval
        elapsed=$((elapsed + interval))
        echo "Still initializing... (${elapsed}s/${timeout}s)"
    done
    
    echo "❌ ERROR: InvenioRDM failed to start within ${timeout} seconds"
    if kill -0 "$invenio_pid" 2>/dev/null; then
        echo "Process is still running but not responding to HTTPS requests."
        echo "Recent InvenioRDM logs:"
        tail -20 invenio.log
    fi
    return 1
}

# Function to initialize InvenioRDM database and indices
initialize_invenio() {
    echo "🔧 Initializing InvenioRDM database and search indices..."
    echo ""
    
    # Check and create the files location directory if it doesn't exist
    if [ ! -d "$FILES_LOCATION" ]; then
        echo "Creating files location directory: $FILES_LOCATION"
        mkdir -p "$FILES_LOCATION"
    fi
    
    # Set proper permissions for the files location directory
    echo "Setting permissions for files location directory: $FILES_LOCATION"
    chmod 755 "$FILES_LOCATION"
    
    # Show message about where files will be stored
    echo "Files will be stored in: $FILES_LOCATION"
    
    local success_count=0
    local total_count=0
    local failed_commands=()
    
    # Array of initialization commands
    local commands=(
        "invenio db init"
        "invenio db create"
        "invenio index init"
        "invenio files location create --default 'default-location' '$FILES_LOCATION'"
        "invenio roles create admin"
    )
    
    # Run each command with environment variables
    for cmd in "${commands[@]}"; do
        total_count=$((total_count + 1))
        echo "Running: $cmd"
        
        if env $(cat ~/.config/lbnl-data-repository/.env | grep -v '^#' | sed 's/[[:space:]]*$//' | xargs) $cmd > /dev/null 2>&1; then
            echo "✅ $cmd - SUCCESS"
            success_count=$((success_count + 1))
        else
            echo "❌ $cmd - FAILED"
            failed_commands+=("$cmd")
        fi
        echo ""
    done
    
    # Show summary
    echo "📊 Initialization Summary:"
    echo "   • Total commands: $total_count"
    echo "   • Successful: $success_count"
    echo "   • Failed: $((total_count - success_count))"
    
    if [ ${#failed_commands[@]} -gt 0 ]; then
        echo ""
        echo "❌ Failed commands:"
        for failed_cmd in "${failed_commands[@]}"; do
            echo "   • $failed_cmd"
        done
        echo ""
        echo "⚠️  Some initialization commands failed. InvenioRDM may not work properly."
        echo "Check the logs above for details."
    else
        echo ""
        echo "✅ All initialization commands completed successfully!"
    fi
    
    return 0
}

# ============================================================================
# Process Management Utilities
# ============================================================================

# Function to get InvenioRDM PID if running
get_invenio_pid() {
    local pid_file="invenio.pid"
    
    # Check if PID file exists
    if [ ! -f "$pid_file" ]; then
        echo ""
        return 1
    fi
    
    # Read PID from file
    local pid=$(cat "$pid_file" 2>/dev/null)
    
    # Validate PID is not empty
    if [ -z "$pid" ]; then
        echo ""
        return 1
    fi
    
    # Check if process is still running
    if kill -0 "$pid" 2>/dev/null; then
        echo "$pid"
        return 0
    else
        # Process not running, clean up stale PID file
        rm -f "$pid_file"
        echo ""
        return 1
    fi
}

# Function to check if InvenioRDM is running
is_invenio_running() {
    local pid=$(get_invenio_pid)
    if [ -n "$pid" ]; then
        return 0  # true - running
    else
        return 1  # false - not running
    fi
}

# Function to cleanup InvenioRDM files
cleanup_invenio_files() {
    local clean_logs=false
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --clean-logs)
                clean_logs=true
                shift
                ;;
            *)
                echo "Unknown option: $1"
                return 1
                ;;
        esac
    done
    
    echo "🧹 Cleaning up InvenioRDM files..."
    
    # Remove PID file if it exists
    if [ -f "invenio.pid" ]; then
        echo "   • Removing invenio.pid"
        rm -f "invenio.pid"
    fi
    
    # Handle log file cleanup
    if [ "$clean_logs" = true ] && [ -f "invenio.log" ]; then
        # Create backup of logs before removal
        local timestamp=$(date +"%Y%m%d_%H%M%S")
        local backup_file="invenio.log.backup_${timestamp}"
        
        echo "   • Creating log backup: $backup_file"
        cp "invenio.log" "$backup_file"
        
        echo "   • Removing invenio.log"
        rm -f "invenio.log"
    fi
    
    echo "✅ Cleanup completed"
}

# Function to stop InvenioRDM process gracefully
stop_invenio_process() {
    local clean_logs=false
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --clean-logs)
                clean_logs=true
                shift
                ;;
            *)
                echo "❌ Unknown option: $1"
                return 1
                ;;
        esac
    done
    
    echo "🛑 Stopping InvenioRDM process..."
    
    # Check if InvenioRDM is running
    if ! is_invenio_running; then
        echo "ℹ️  InvenioRDM is not currently running"
        return 0
    fi
    
    local pid=$(get_invenio_pid)
    if [ -z "$pid" ]; then
        echo "❌ Could not determine InvenioRDM process ID"
        return 1
    fi
    
    echo "   • Found InvenioRDM process (PID: $pid)"
    
    # Check if PID file exists but process is already dead
    if ! kill -0 "$pid" 2>/dev/null; then
        echo "⚠️  Process $pid is not running (stale PID file)"
        cleanup_invenio_files
        echo "✅ Cleaned up stale PID file"
        return 0
    fi
    
    # Attempt graceful shutdown with SIGTERM
    echo "   • Sending SIGTERM signal for graceful shutdown..."
    if ! kill -TERM "$pid" 2>/dev/null; then
        echo "❌ Failed to send SIGTERM signal (permission denied or process not found)"
        return 1
    fi
    
    # Wait up to 30 seconds for graceful shutdown
    local wait_time=0
    local max_wait=30
    echo "   • Waiting for graceful shutdown (up to ${max_wait}s)..."
    
    while [ $wait_time -lt $max_wait ]; do
        if ! kill -0 "$pid" 2>/dev/null; then
            echo "✅ Process stopped gracefully after ${wait_time}s"
            cleanup_invenio_files
            if [ "$clean_logs" = true ]; then
                cleanup_invenio_files --clean-logs
            fi
            echo "✅ InvenioRDM stopped successfully"
            return 0
        fi
        
        sleep 1
        wait_time=$((wait_time + 1))
        
        # Show progress every 5 seconds
        if [ $((wait_time % 5)) -eq 0 ]; then
            echo "   • Still waiting... (${wait_time}/${max_wait}s)"
        fi
    done
    
    # If graceful shutdown failed, use SIGKILL
    echo "⚠️  Graceful shutdown timed out, forcing termination..."
    
    if ! kill -0 "$pid" 2>/dev/null; then
        echo "✅ Process stopped during timeout period"
        cleanup_invenio_files
        if [ "$clean_logs" = true ]; then
            cleanup_invenio_files --clean-logs
        fi
        echo "✅ InvenioRDM stopped successfully"
        return 0
    fi
    
    echo "   • Sending SIGKILL signal..."
    if ! kill -KILL "$pid" 2>/dev/null; then
        echo "❌ Failed to send SIGKILL signal (permission denied or process not found)"
        return 1
    fi
    
    # Wait a moment for SIGKILL to take effect
    sleep 2
    
    if kill -0 "$pid" 2>/dev/null; then
        echo "❌ Process $pid could not be terminated"
        return 1
    fi
    
    echo "✅ Process forcefully terminated"
    cleanup_invenio_files
    if [ "$clean_logs" = true ]; then
        cleanup_invenio_files --clean-logs
    fi
    echo "✅ InvenioRDM stopped successfully"
    return 0
}
# Function to stop all services while preserving data
stop_all_services() {
    echo "🛑 Stopping All InvenioRDM Services"
    echo "===================================="
    echo "ℹ️  This will stop all services while preserving data volumes"
    echo ""
    
    # Step 1: Stop InvenioRDM process first
    echo "🔄 Step 1: Stopping InvenioRDM process..."
    if stop_invenio_process; then
        echo "✅ InvenioRDM process stopped successfully"
    else
        echo "⚠️  InvenioRDM process may not have been running or failed to stop cleanly"
    fi
    echo ""
    
    # Step 2: Stop Docker containers
    echo "🔄 Step 2: Stopping Docker containers..."
    
    # Load environment variables
    if [ -f ~/.config/lbnl-data-repository/.env ]; then
        echo "📋 Loading environment configuration..."
        
        # Stop containers using docker-compose down (without -v to preserve volumes)
        if env $(cat ~/.config/lbnl-data-repository/.env | grep -v '^#' | sed 's/[[:space:]]*$//' | xargs) docker-compose -f docker-compose.yml down --remove-orphans; then
            echo "✅ Docker containers stopped successfully"
        else
            echo "❌ Failed to stop Docker containers"
            return 1
        fi
    else
        echo "⚠️  Environment file not found at ~/.config/lbnl-data-repository/.env"
        echo "🔄 Attempting to stop containers without environment..."
        
        if docker-compose -f docker-compose.yml down --remove-orphans 2>/dev/null; then
            echo "✅ Docker containers stopped successfully"
        else
            echo "❌ Failed to stop Docker containers"
            return 1
        fi
    fi
    echo ""
    
    # Step 3: Verify all containers are stopped
    echo "🔄 Step 3: Verifying container shutdown..."
    sleep 2  # Give containers time to fully stop
    
    local running_containers=$(docker ps -q --filter "label=com.docker.compose.project" 2>/dev/null | wc -l | tr -d ' ')
    if [ "$running_containers" -eq 0 ]; then
        echo "✅ All containers confirmed stopped"
    else
        echo "⚠️  Warning: $running_containers container(s) may still be running"
        echo "   Running containers:"
        docker ps --format "table {{.Names}}\t{{.Status}}" --filter "label=com.docker.compose.project" 2>/dev/null | sed 's/^/   /'
    fi
    echo ""
    
    # Step 4: Show preserved data/volumes
    echo "💾 Data Preservation Status"
    echo "=========================="
    echo "✅ The following data has been preserved:"
    echo ""
    
    # List Docker volumes
    local volumes=$(docker volume ls -q --filter "label=com.docker.compose.project" 2>/dev/null)
    if [ -n "$volumes" ]; then
        echo "🗄️  Docker Volumes:"
        echo "$volumes" | while read -r volume; do
            if [ -n "$volume" ]; then
                local size=$(docker system df -v 2>/dev/null | grep "$volume" | awk '{print $3}' || echo "Unknown")
                echo "   📦 $volume (Size: $size)"
            fi
        done
    else
        echo "🗄️  Docker Volumes: None found or unable to list"
    fi
    echo ""
    
    # Show other preserved data locations
    echo "📁 Other Preserved Data:"
    local data_locations=(
        "app_data/"
        "static/"
        "templates/"
        "assets/"
        "site/"
        "invenio.cfg"
        ".invenio"
    )
    
    for location in "${data_locations[@]}"; do
        if [ -e "$location" ]; then
            if [ -d "$location" ]; then
                local file_count=$(find "$location" -type f 2>/dev/null | wc -l | tr -d ' ')
                echo "   📂 $location ($file_count files)"
            else
                echo "   📄 $location"
            fi
        fi
    done
    echo ""
    
    # Final status
    echo "🎯 Shutdown Summary"
    echo "=================="
    echo "✅ InvenioRDM process: Stopped"
    echo "✅ Docker containers: Stopped"
    echo "✅ Data volumes: Preserved"
    echo "✅ Configuration files: Preserved"
    echo "✅ Application data: Preserved"
    echo ""
    echo "💡 To restart services, run: $0 --start"
    echo "💡 To view status, run: $0 --status"
    
    return 0
}

# Function to restart services
restart_services() {
    echo "🔄 Restarting InvenioRDM services..."

    # Filter out --restart from the arguments and add restart marker
    local args=()
    for arg in "${ORIGINAL_ARGS[@]}"; do
        if [[ "$arg" != "--restart" ]]; then
            args+=("$arg")
        fi
    done
    
    # Add internal restart marker to track this is a restart operation
    args+=("--internal-restart-marker")

    # Stop all services
    stop_all_services

    # Wait for clean shutdown
    echo "🕒 Waiting for services to shut down completely..."
    sleep 5

    # Reconstruct the startup command with preserved arguments
    local startup_command="./run_invenio.sh ${args[*]}"
    echo "🛠️  Reconstructing startup command: $startup_command"

    # Execute the startup command
    eval "$startup_command"

    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        echo "❌ ERROR: Restart failed with exit code $exit_code. Please check the logs for more details."
        exit 1
    fi

    echo "✅ Restart completed successfully."
}

# Function to show detailed status
show_detailed_status() {
    echo "📊 InvenioRDM Process Status"
    echo "================================"
    
    # Check InvenioRDM process status
    local pid=$(get_invenio_pid)
    if [ -n "$pid" ]; then
        echo "✅ InvenioRDM: Running (PID: $pid)"
        
        # Show process details
        if command -v ps >/dev/null 2>&1; then
            echo "   Process details:"
            ps -p "$pid" -o pid,ppid,pcpu,pmem,etime,cmd 2>/dev/null | head -2 | tail -1 | sed 's/^/   /'
        fi
        
        # Check if process is responding (if port is known)
        if [ -f "invenio.pid" ]; then
            local port=$(lsof -p "$pid" -i -P -n 2>/dev/null | grep LISTEN | grep -o ':\([0-9]*\)' | head -1 | cut -d: -f2)
            if [ -n "$port" ]; then
                echo "   Listening on port: $port"
                if curl -k -s -f "https://127.0.0.1:$port" >/dev/null 2>&1; then
                    echo "   Status: ✅ Responding to HTTPS requests"
                else
                    echo "   Status: ⚠️  Not responding to HTTPS requests"
                fi
            fi
        fi
    else
        echo "❌ InvenioRDM: Not running"
    fi
    
    echo ""
    echo "🐳 Container Status Summary"
    echo "================================"
    
    # Check if docker-compose is available and show container status
    if command -v docker-compose >/dev/null 2>&1 && [ -f "docker-compose.yml" ]; then
        # Load environment and show container status
        if [ -f ~/.config/lbnl-data-repository/.env ]; then
            env $(cat ~/.config/lbnl-data-repository/.env | grep -v '^#' | sed 's/[[:space:]]*$//' | xargs) docker-compose -f docker-compose.yml ps --format table
        else
            echo "⚠️  Environment file not found, showing basic container status:"
            docker-compose -f docker-compose.yml ps --format table 2>/dev/null || echo "❌ Unable to get container status"
        fi
    else
        echo "⚠️  docker-compose or docker-compose.yml not available"
    fi
    
    echo ""
    echo "🔌 Port Usage Summary"
    echo "================================"
    
    # Check key service ports
    local ports=(5002 5601 5050 15672 5432 6379 9200 443 80)
    local port_names=("InvenioRDM" "OpenSearch Dashboards" "PgAdmin" "RabbitMQ Management" "PostgreSQL" "Redis" "OpenSearch" "HTTPS Frontend" "HTTP Frontend")
    
    for i in "${!ports[@]}"; do
        local port="${ports[$i]}"
        local name="${port_names[$i]}"
        
        if lsof -i ":$port" >/dev/null 2>&1; then
            local process_info=$(lsof -i ":$port" -P -n 2>/dev/null | grep LISTEN | head -1 | awk '{print $1, $2}')
            echo "✅ Port $port ($name): In use by $process_info"
        else
            echo "⚪ Port $port ($name): Available"
        fi
    done
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --debug)
            DEBUG_MODE=true
            shift
            ;;
        --port)
            if [[ -n $2 && $2 =~ ^[0-9]+$ ]]; then
                INVENIO_PORT=$2
            else
                echo "❌ ERROR: --port requires a numeric argument"
                exit 1
            fi
            shift 2
            ;;
        --invenio)
            START_INVENIO=true
            shift
            ;;
        --reset)
            RESET_MODE=true
            shift
            ;;
        --stop)
            STOP_MODE=true
            shift
            ;;
        --stop-all)
            STOP_ALL_MODE=true
            shift
            ;;
        --restart)
            RESTART_MODE=true
            shift
            ;;
        --status)
            STATUS_MODE=true
            shift
            ;;
        --internal-restart-marker)
            # Internal flag to track restart operations
            IS_RESTART_OPERATION=true
            shift
            ;;
        --help)
            echo "Usage: $0 [--debug] [--port <port>] [--invenio] [--reset] [--stop] [--stop-all] [--restart] [--status]"
            echo "Options:"
            echo "  --debug      Start containers only (for debugging)"
            echo "  --port       Specify InvenioRDM port (default: 5002)"
            echo "  --invenio    Start InvenioRDM after containers are ready"
            echo "  --reset      Reset all data and reinitialize (DESTRUCTIVE)"
            echo "  --stop       Stop InvenioRDM process only (containers keep running)"
            echo "  --stop-all   Stop InvenioRDM process + all containers (preserve data/volumes)"
            echo "  --restart    Stop everything, then restart with same options"
            echo "  --status     Show detailed status of InvenioRDM process and all containers"
            echo "  --help       Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0                           # Start containers only"
            echo "  $0 --invenio                # Start containers + InvenioRDM on port 5002"
            echo "  $0 --invenio --port 8080    # Start containers + InvenioRDM on port 8080"
            echo "  $0 --debug                  # Start containers only (debug mode)"
            echo "  $0 --reset                   # Reset all data + containers only"
            echo "  $0 --reset --invenio         # Reset all data + containers + InvenioRDM"
            echo "  $0 --reset --invenio --port 8080  # Reset + containers + InvenioRDM on port 8080"
            echo "  $0 --stop                    # Stop InvenioRDM process only"
            echo "  $0 --stop-all               # Stop InvenioRDM + all containers"
            echo "  $0 --restart --invenio      # Restart everything + InvenioRDM"
            echo "  $0 --status                 # Show detailed status"
            exit 0
            ;;
        *)
            echo "❌ ERROR: Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Validate that only one primary mode is selected
mode_count=0
selected_modes=""
if [ "$STATUS_MODE" = true ]; then mode_count=$((mode_count + 1)); selected_modes="$selected_modes --status"; fi
if [ "$STOP_MODE" = true ]; then mode_count=$((mode_count + 1)); selected_modes="$selected_modes --stop"; fi
if [ "$STOP_ALL_MODE" = true ]; then mode_count=$((mode_count + 1)); selected_modes="$selected_modes --stop-all"; fi
if [ "$RESTART_MODE" = true ]; then mode_count=$((mode_count + 1)); selected_modes="$selected_modes --restart"; fi
if [ "$RESET_MODE" = true ]; then mode_count=$((mode_count + 1)); selected_modes="$selected_modes --reset"; fi

if [ $mode_count -gt 1 ]; then
    echo "❌ ERROR: Multiple conflicting modes selected:$selected_modes"
    echo "Please choose only one primary mode. Use --help for usage information."
    exit 1
fi

# Handle the new modes before existing startup logic
if [ "$STATUS_MODE" = true ]; then
    show_detailed_status
    exit 0
elif [ "$STOP_MODE" = true ]; then
    echo "🛑 Stopping InvenioRDM process..."
    if stop_invenio_process; then
        echo "✅ InvenioRDM process stopped successfully"
        exit 0
    else
        echo "❌ Failed to stop InvenioRDM process"
        exit 1
    fi
elif [ "$STOP_ALL_MODE" = true ]; then
    echo "🛑 Stopping all services (InvenioRDM + containers)..."
    if stop_all_services; then
        echo "✅ All services stopped successfully"
        exit 0
    else
        echo "❌ Failed to stop all services"
        exit 1
    fi
elif [ "$RESTART_MODE" = true ]; then
    echo "🔄 Initiating restart sequence..."
    if restart_services; then
        exit 0
    else
        echo "❌ Restart sequence failed"
        exit 1
    fi
fi

# Update mode announcement
if [ "$RESET_MODE" = true ]; then
    if [ "$START_INVENIO" = true ]; then
        echo "🔄 Starting in RESET + FULL mode (reset + containers + InvenioRDM on port $INVENIO_PORT)"
    else
        echo "🔄 Starting in RESET + CONTAINER mode (reset + containers only)"
    fi
elif [ "$START_INVENIO" = true ]; then
    echo "🚀 Starting in FULL mode (containers + InvenioRDM on port $INVENIO_PORT)"
elif [ "$DEBUG_MODE" = true ]; then
    echo "🔧 Starting in DEBUG mode (containers only)"
else
    echo "📦 Starting in CONTAINER mode (containers only)"
fi

# Perform reset if requested
if [ "$RESET_MODE" = true ]; then
    perform_reset_and_init
fi

# Build/pull images and show progress
echo "Building/pulling Docker images..."
env $(cat ~/.config/lbnl-data-repository/.env | grep -v '^#' | sed 's/[[:space:]]*$//' | xargs) docker-compose -f docker-compose.yml build --progress=plain

echo "DEBUG: OPENSEARCH_ADMIN_PASSWORD value being passed: '${OPENSEARCH_ADMIN_PASSWORD}'"

echo "Starting services..."
env $(cat ~/.config/lbnl-data-repository/.env | grep -v '^#' | sed 's/[[:space:]]*$//' | xargs) docker-compose -f docker-compose.yml up -d --remove-orphans

# Function to check if all services are running and healthy
check_services_ready() {
    # Get list of services that should be running
    services=$(env $(cat ~/.config/lbnl-data-repository/.env | grep -v '^#' | sed 's/[[:space:]]*$//' | xargs) docker-compose -f docker-compose.yml config --services)
    
    echo "Checking service status..."
    
    for service in $services; do
        # Get container status
        container_status=$(env $(cat ~/.config/lbnl-data-repository/.env | grep -v '^#' | sed 's/[[:space:]]*$//' | xargs) docker-compose -f docker-compose.yml ps -q $service | xargs docker inspect -f '{{.State.Status}}' 2>/dev/null || echo "unknown")
        container_running=$(env $(cat ~/.config/lbnl-data-repository/.env | grep -v '^#' | sed 's/[[:space:]]*$//' | xargs) docker-compose -f docker-compose.yml ps -q $service | xargs docker inspect -f '{{.State.Running}}' 2>/dev/null || echo "false")
        restart_count=$(env $(cat ~/.config/lbnl-data-repository/.env | grep -v '^#' | sed 's/[[:space:]]*$//' | xargs) docker-compose -f docker-compose.yml ps -q $service | xargs docker inspect -f '{{.RestartCount}}' 2>/dev/null || echo "0")
        
        echo "Service $service: Status=$container_status, Running=$container_running, Restarts=$restart_count"
        
        # Check if container is restarting
        if [ "$restart_count" -gt "3" ]; then
            echo "ERROR: Service $service has restarted $restart_count times!"
            echo "Last 20 lines of logs for $service:"
            env $(cat ~/.config/lbnl-data-repository/.env | grep -v '^#' | sed 's/[[:space:]]*$//' | xargs) docker-compose -f docker-compose.yml logs --tail=20 $service
            return 1
        fi
        
        # Check if container is running
        if [ "$container_running" != "true" ]; then
            if [ "$container_status" = "restarting" ]; then
                echo "WARNING: Service $service is restarting..."
                return 1
            elif [ "$container_status" = "exited" ]; then
                echo "ERROR: Service $service has exited!"
                echo "Last 10 lines of logs for $service:"
                env $(cat ~/.config/lbnl-data-repository/.env | grep -v '^#' | sed 's/[[:space:]]*$//' | xargs) docker-compose -f docker-compose.yml logs --tail=10 $service
                return 1
            else
                echo "WARNING: Service $service is not running (status: $container_status)"
                return 1
            fi
        fi
        
        # Additional health checks for critical services (only if container is running)
        case $service in
            "db")
                if ! env $(cat ~/.config/lbnl-data-repository/.env | grep -v '^#' | sed 's/[[:space:]]*$//' | xargs) docker-compose -f docker-compose.yml exec -T db pg_isready -U ${POSTGRES_USER:-lbnl-data-repository} > /dev/null 2>&1; then
                    echo "WARNING: Database not ready yet"
                    return 1
                fi
                echo "✓ Database is ready"
                ;;
            "search")
                # Check if OpenSearch is responding (with proper SSL handling)
                if ! env $(cat ~/.config/lbnl-data-repository/.env | grep -v '^#' | sed 's/[[:space:]]*$//' | xargs) docker-compose -f docker-compose.yml exec -T search curl -k -u admin:${OPENSEARCH_ADMIN_PASSWORD:-admin} -s https://localhost:9200/_cluster/health > /dev/null 2>&1; then
                    echo "WARNING: OpenSearch not ready yet"
                    # Show OpenSearch logs if it's failing
                    echo "Recent OpenSearch logs:"
                    env $(cat ~/.config/lbnl-data-repository/.env | grep -v '^#' | sed 's/[[:space:]]*$//' | xargs) docker-compose -f docker-compose.yml logs --tail=5 search
                    return 1
                fi
                echo "✓ OpenSearch is ready"
                ;;
            "cache")
                if ! env $(cat ~/.config/lbnl-data-repository/.env | grep -v '^#' | sed 's/[[:space:]]*$//' | xargs) docker-compose -f docker-compose.yml exec -T cache redis-cli ping > /dev/null 2>&1; then
                    echo "WARNING: Redis cache not ready yet"
                    return 1
                fi
                echo "✓ Redis cache is ready"
                ;;
            "mq")
                if ! env $(cat ~/.config/lbnl-data-repository/.env | grep -v '^#' | sed 's/[[:space:]]*$//' | xargs) docker-compose -f docker-compose.yml exec -T mq rabbitmq-diagnostics -q ping > /dev/null 2>&1; then
                    echo "WARNING: RabbitMQ not ready yet"
                    return 1
                fi
                echo "✓ RabbitMQ is ready"
                ;;
            "frontend")
                # Check if nginx is responding
                if ! env $(cat ~/.config/lbnl-data-repository/.env | grep -v '^#' | sed 's/[[:space:]]*$//' | xargs) docker-compose -f docker-compose.yml exec -T frontend curl -k -s https://localhost:443 > /dev/null 2>&1; then
                    echo "WARNING: Frontend not ready yet"
                    echo "Recent frontend logs:"
                    env $(cat ~/.config/lbnl-data-repository/.env | grep -v '^#' | sed 's/[[:space:]]*$//' | xargs) docker-compose -f docker-compose.yml logs --tail=5 frontend
                    return 1
                fi
                echo "✓ Frontend is ready"
                ;;
        esac
    done
    return 0
}

# Show initial container status
echo "Initial container status:"
env $(cat ~/.config/lbnl-data-repository/.env | grep -v '^#' | sed 's/[[:space:]]*$//' | xargs) docker-compose -f docker-compose.yml ps

# Check for common issues
echo "Checking for common configuration issues..."

# Check if SSL certificates exist for frontend and search
if [ ! -f "${HOME}/.config/lbnl-data-repository/ssl/server.pem" ]; then
    echo "ERROR: SSL certificate not found at ${HOME}/.config/lbnl-data-repository/ssl/server.pem"
    echo "This will cause frontend and search containers to fail!"
fi

if [ ! -f "${HOME}/.config/lbnl-data-repository/ssl/server-key.pem" ]; then
    echo "ERROR: SSL private key not found at ${HOME}/.config/lbnl-data-repository/ssl/server-key.pem"
    echo "This will cause frontend and search containers to fail!"
fi

if [ ! -f "${HOME}/.config/lbnl-data-repository/ssl/ca.pem" ]; then
    echo "ERROR: SSL CA certificate not found at ${HOME}/.config/lbnl-data-repository/ssl/ca.pem"
    echo "This will cause search container to fail!"
fi

# Check if OPENSEARCH_ADMIN_PASSWORD is set in .env file
if ! grep -q "OPENSEARCH_ADMIN_PASSWORD=" ~/.config/lbnl-data-repository/.env 2>/dev/null; then
    echo "WARNING: OPENSEARCH_ADMIN_PASSWORD not found in .env file"
    echo "Search container may fail to start properly"
else
    echo "✓ OPENSEARCH_ADMIN_PASSWORD found in .env file"
fi

echo "Starting health check loop..."

# Wait loop with timeout
timeout=300  # 5 minutes timeout
elapsed=0
interval=5

while ! check_services_ready; do
    if [ $elapsed -ge $timeout ]; then
        echo "TIMEOUT: Services failed to become ready after ${timeout} seconds"
        echo ""
        echo "Final container status:"
        env $(cat ~/.config/lbnl-data-repository/.env | grep -v '^#' | sed 's/[[:space:]]*$//' | xargs) docker-compose -f docker-compose.yml ps
        echo ""
        echo "Logs for problematic containers:"
        for service in frontend search; do
            echo "=== Logs for $service ==="
            env $(cat ~/.config/lbnl-data-repository/.env | grep -v '^#' | sed 's/[[:space:]]*$//' | xargs) docker-compose -f docker-compose.yml logs --tail=30 $service
            echo ""
        done
        exit 1
    fi
    
    echo "Services not ready yet, waiting... (${elapsed}s/${timeout}s)"
    sleep $interval
    elapsed=$((elapsed + interval))
done

echo "All services are ready!"

# Initialize database if reset was performed
if [ "$RESET_MODE" = true ]; then
    echo ""
    initialize_invenio
fi

# Start InvenioRDM if requested
if [ "$START_INVENIO" = true ]; then
    echo ""
    echo "🚀 Starting InvenioRDM..."
    if start_invenio_rdm "$INVENIO_PORT"; then
        echo ""
        echo "🎉 =================================================="
        if [ "$RESET_MODE" = true ]; then
            echo "✅       RESET + INITIALIZATION COMPLETE!"
        elif [ "$IS_RESTART_OPERATION" = true ]; then
            echo "✅           RESTART COMPLETE!"
        else
            echo "✅           ALL SERVICES READY!"
        fi
        echo "🎉 =================================================="
        echo ""
        echo "🌐 Service URLs:"
        echo "   • InvenioRDM:             https://127.0.0.1:$INVENIO_PORT"
        echo "   • OpenSearch Dashboards:  https://127.0.0.1:5601"
        echo "   • PgAdmin:                http://127.0.0.1:5050"
        echo "   • RabbitMQ Management:    http://127.0.0.1:15672"
        echo ""
        echo "🛠️  Management Commands:"
        echo "   • Stop InvenioRDM only:    $0 --stop"
        echo "   • Stop all services:       $0 --stop-all"
        echo "   • Restart services:        $0 --restart --invenio"
        echo "   • Check detailed status:   $0 --status"
        echo "   • View logs:               docker-compose -f docker-compose.yml logs -f <service>"
        echo "   • InvenioRDM logs:         tail -f invenio.log"
        echo ""
        echo "🚀 Your development environment is ready!"
        echo "=================================================="
    else
        echo "❌ InvenioRDM startup failed"
        exit 1
    fi
else
    echo ""
    if [ "$RESET_MODE" = true ]; then
        echo "📦 Reset + Container mode: Services reset and started successfully"
        echo "   • Database and search indices have been initialized"
    else
        echo "📦 Container mode: Services started successfully"
    fi
    echo "   • Use 'docker-compose -f docker-compose.yml ps' to check status"
    echo "   • Use 'docker-compose -f docker-compose.yml logs -f <service>' to view logs"
    echo "   • To start InvenioRDM manually:"
    echo "     env \$(cat ~/.config/lbnl-data-repository/.env | grep -v '^#' | sed 's/[[:space:]]*$//' | xargs) invenio run --host 127.0.0.1 --port $INVENIO_PORT --cert ~/.config/lbnl-data-repository/ssl/server.pem --key ~/.config/lbnl-data-repository/ssl/server-key.pem"
    echo "   • Or restart with: $0 --invenio --port $INVENIO_PORT"
fi

