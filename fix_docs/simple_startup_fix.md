## Edit Instructions for `run_service_containers.sh`

### **1. Add InvenioRDM startup function**
**Insert after line 87 (after the `check_services_ready()` function):**

```bash
# Function to start InvenioRDM with proper environment
start_invenio_rdm() {
    local port=${1:-5002}
    echo "🚀 Starting InvenioRDM on port $port..."
    
    # Check if port is available
    if lsof -i ":$port" >/dev/null 2>&1; then
        echo "❌ ERROR: Port $port is already in use"
        echo "Please choose a different port or stop the service using that port."
        return 1
    fi
    
    # Start InvenioRDM with environment variables loaded
    echo "Loading environment and starting InvenioRDM..."
    env $(cat ~/.config/lbnl-data-repository/.env | grep -v '^#' | xargs) \
        nohup invenio run --host 127.0.0.1 --port "$port" > invenio.log 2>&1 &
    
    local invenio_pid=$!
    echo "$invenio_pid" > invenio.pid
    echo "InvenioRDM started with PID: $invenio_pid"
    
    # Wait for InvenioRDM to start up
    echo "Waiting for InvenioRDM to initialize..."
    local timeout=120
    local elapsed=0
    local interval=3
    
    while [ $elapsed -lt $timeout ]; do
        if kill -0 "$invenio_pid" 2>/dev/null; then
            if curl -s -f "http://127.0.0.1:$port" >/dev/null 2>&1; then
                echo "✅ InvenioRDM is responding on port $port"
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
        echo "Process is still running but not responding to HTTP requests."
        echo "Recent InvenioRDM logs:"
        tail -20 invenio.log
    fi
    return 1
}
```

### **2. Add --invenio flag to argument parsing**
**Replace lines 6-8 (the default values section) with:**

```bash
# Default values
DEBUG_MODE=false
INVENIO_PORT=5002
START_INVENIO=false
```

### **3. Update argument parsing loop**
**Replace the existing argument parsing while loop (lines 10-35) with:**

```bash
# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --debug)
            DEBUG_MODE=true
            shift
            ;;
        --port)
            if [ -z "$2" ]; then
                echo "❌ ERROR: --port requires a port number"
                exit 1
            fi
            INVENIO_PORT="$2"
            # Validate port number
            if ! [[ "$INVENIO_PORT" =~ ^[0-9]+$ ]] || [ "$INVENIO_PORT" -lt 1024 ] || [ "$INVENIO_PORT" -gt 65535 ]; then
                echo "❌ ERROR: Port must be a number between 1024 and 65535"
                exit 1
            fi
            shift 2
            ;;
        --invenio)
            START_INVENIO=true
            shift
            ;;
        --help)
            echo "Usage: $0 [--debug] [--port <port>] [--invenio]"
            echo "Options:"
            echo "  --debug    Start containers only (for debugging)"
            echo "  --port     Specify InvenioRDM port (default: 5002)"
            echo "  --invenio  Start InvenioRDM after containers are ready"
            echo "  --help     Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0                           # Start containers only"
            echo "  $0 --invenio                # Start containers + InvenioRDM on port 5002"
            echo "  $0 --invenio --port 8080    # Start containers + InvenioRDM on port 8080"
            echo "  $0 --debug                  # Start containers only (debug mode)"
            exit 0
            ;;
        *)
            echo "❌ ERROR: Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done
```

### **4. Update the mode announcement**
**Replace line 54 (the mode announcement) with:**

```bash
if [ "$START_INVENIO" = true ]; then
    echo "🚀 Starting in FULL mode (containers + InvenioRDM on port $INVENIO_PORT)"
elif [ "$DEBUG_MODE" = true ]; then
    echo "🔧 Starting in DEBUG mode (containers only)"
else
    echo "📦 Starting in CONTAINER mode (containers only)"
fi
```

### **5. Update the main execution flow**
**Replace the final section (around line 170, after "All services are ready!") with:**

```bash
echo "All services are ready!"

# Start InvenioRDM if requested
if [ "$START_INVENIO" = true ]; then
    echo ""
    echo "🚀 Starting InvenioRDM..."
    if start_invenio_rdm "$INVENIO_PORT"; then
        echo ""
        echo "🎉 =================================================="
        echo "✅           ALL SERVICES READY!"
        echo "🎉 =================================================="
        echo ""
        echo "🌐 Service URLs:"
        echo "   • InvenioRDM:             http://127.0.0.1:$INVENIO_PORT"
        echo "   • OpenSearch Dashboards:  https://127.0.0.1:5601"
        echo "   • PgAdmin:                http://127.0.0.1:5050"
        echo "   • RabbitMQ Management:    http://127.0.0.1:15672"
        echo ""
        echo "🛠️  Management Commands:"
        echo "   • Stop InvenioRDM: kill \$(cat invenio.pid) && rm -f invenio.pid"
        echo "   • Check status:    docker-compose -f docker-compose.yml ps"
        echo "   • View logs:       docker-compose -f docker-compose.yml logs -f <service>"
        echo "   • InvenioRDM logs: tail -f invenio.log"
        echo ""
        echo "🚀 Your development environment is ready!"
        echo "=================================================="
    else
        echo "❌ InvenioRDM startup failed"
        exit 1
    fi
else
    echo ""
    echo "📦 Container mode: Services started successfully"
    echo "   • Use 'docker-compose -f docker-compose.yml ps' to check status"
    echo "   • Use 'docker-compose -f docker-compose.yml logs -f <service>' to view logs"
    echo "   • To start InvenioRDM manually:"
    echo "     env \$(cat ~/.config/lbnl-data-repository/.env | grep -v '^#' | xargs) invenio run --host 127.0.0.1 --port $INVENIO_PORT"
    echo "   • Or restart with: $0 --invenio --port $INVENIO_PORT"
fi
```

### **6. Update cleanup function for InvenioRDM**
**Replace the existing `cleanup_on_error()` function (around line 38) with:**

```bash
cleanup_on_error() {
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        echo ""
        echo "❌ Script failed with exit code $exit_code"
        echo "🔍 Troubleshooting tips:"
        echo "   • Check service logs: docker-compose -f docker-compose.yml logs <service>"
        echo "   • Verify environment: cat ~/.config/lbnl-data-repository/.env"
        echo "   • Check certificates: ls -la ~/.config/lbnl-data-repository/ssl/"
        echo "   • Restart in debug mode: $0 --debug"
        if [ -f invenio.log ]; then
            echo "   • Check InvenioRDM logs: tail -50 invenio.log"
        fi
        if [ -f invenio.pid ]; then
            echo "   • Stop InvenioRDM: kill \$(cat invenio.pid) && rm -f invenio.pid"
        fi
    fi
}
```

## Usage Examples

After these edits, the script will support:

```bash
# Start only containers (existing behavior)
./run_service_containers.sh

# Start containers + InvenioRDM on default port 5002
./run_service_containers.sh --invenio

# Start containers + InvenioRDM on custom port
./run_service_containers.sh --invenio --port 8080

# Debug mode (containers only)
./run_service_containers.sh --debug
```

The key improvements:
1. **Environment variables are properly loaded** using your exact command pattern
2. **Port is configurable** via `--port` flag
3. **InvenioRDM startup is optional** via `--invenio` flag
4. **Proper health checking** for InvenioRDM startup
