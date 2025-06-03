#!/bin/bash

# Default values
DEBUG_MODE=false
START_INVENIO=false
INVENIO_PORT=5002
RESET_MODE=false

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
    
    local success_count=0
    local total_count=0
    local failed_commands=()
    
    # Array of initialization commands
    local commands=(
        "invenio db init"
        "invenio db create"
        "invenio index init"
        "invenio files location create --default 'default-location' /tmp/data"
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
        --help)
            echo "Usage: $0 [--debug] [--port <port>] [--invenio] [--reset]"
            echo "Options:"
            echo "  --debug    Start containers only (for debugging)"
            echo "  --port     Specify InvenioRDM port (default: 5002)"
            echo "  --invenio  Start InvenioRDM after containers are ready"
            echo "  --reset    Reset all data and reinitialize (DESTRUCTIVE)"
            echo "  --help     Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0                           # Start containers only"
            echo "  $0 --invenio                # Start containers + InvenioRDM on port 5002"
            echo "  $0 --invenio --port 8080    # Start containers + InvenioRDM on port 8080"
            echo "  $0 --debug                  # Start containers only (debug mode)"
            echo "  $0 --reset                   # Reset all data + containers only"
            echo "  $0 --reset --invenio         # Reset all data + containers + InvenioRDM"
            echo "  $0 --reset --invenio --port 8080  # Reset + containers + InvenioRDM on port 8080"
            exit 0
            ;;
        *)
            echo "❌ ERROR: Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

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

