#!/bin/bash

# Default values
DEBUG_MODE=false
START_INVENIO=false
INVENIO_PORT=5002

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

# Update mode announcement
if [ "$START_INVENIO" = true ]; then
    echo "🚀 Starting in FULL mode (containers + InvenioRDM on port $INVENIO_PORT)"
elif [ "$DEBUG_MODE" = true ]; then
    echo "🔧 Starting in DEBUG mode (containers only)"
else
    echo "📦 Starting in CONTAINER mode (containers only)"
fi

# Build/pull images and show progress
echo "Building/pulling Docker images..."
env $(cat ~/.config/lbnl-data-repository/.env | grep -v '^#' | xargs) docker-compose -f docker-compose.yml build --progress=plain

echo "DEBUG: OPENSEARCH_ADMIN_PASSWORD value being passed: '${OPENSEARCH_ADMIN_PASSWORD}'"

echo "Starting services..."
env $(cat ~/.config/lbnl-data-repository/.env | grep -v '^#' | xargs) docker-compose -f docker-compose.yml up -d --remove-orphans

# Function to check if all services are running and healthy
check_services_ready() {
    # Get list of services that should be running
    services=$(env $(cat ~/.config/lbnl-data-repository/.env | grep -v '^#' | xargs) docker-compose -f docker-compose.yml config --services)
    
    echo "Checking service status..."
    
    for service in $services; do
        # Get container status
        container_status=$(env $(cat ~/.config/lbnl-data-repository/.env | grep -v '^#' | xargs) docker-compose -f docker-compose.yml ps -q $service | xargs docker inspect -f '{{.State.Status}}' 2>/dev/null || echo "unknown")
        container_running=$(env $(cat ~/.config/lbnl-data-repository/.env | grep -v '^#' | xargs) docker-compose -f docker-compose.yml ps -q $service | xargs docker inspect -f '{{.State.Running}}' 2>/dev/null || echo "false")
        restart_count=$(env $(cat ~/.config/lbnl-data-repository/.env | grep -v '^#' | xargs) docker-compose -f docker-compose.yml ps -q $service | xargs docker inspect -f '{{.RestartCount}}' 2>/dev/null || echo "0")
        
        echo "Service $service: Status=$container_status, Running=$container_running, Restarts=$restart_count"
        
        # Check if container is restarting
        if [ "$restart_count" -gt "3" ]; then
            echo "ERROR: Service $service has restarted $restart_count times!"
            echo "Last 20 lines of logs for $service:"
            env $(cat ~/.config/lbnl-data-repository/.env | grep -v '^#' | xargs) docker-compose -f docker-compose.yml logs --tail=20 $service
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
                env $(cat ~/.config/lbnl-data-repository/.env | grep -v '^#' | xargs) docker-compose -f docker-compose.yml logs --tail=10 $service
                return 1
            else
                echo "WARNING: Service $service is not running (status: $container_status)"
                return 1
            fi
        fi
        
        # Additional health checks for critical services (only if container is running)
        case $service in
            "db")
                if ! env $(cat ~/.config/lbnl-data-repository/.env | grep -v '^#' | xargs) docker-compose -f docker-compose.yml exec -T db pg_isready -U lbnl-data-repository > /dev/null 2>&1; then
                    echo "WARNING: Database not ready yet"
                    return 1
                fi
                echo "✓ Database is ready"
                ;;
            "search")
                # Check if OpenSearch is responding (with proper SSL handling)
                if ! env $(cat ~/.config/lbnl-data-repository/.env | grep -v '^#' | xargs) docker-compose -f docker-compose.yml exec -T search curl -k -u admin:${OPENSEARCH_ADMIN_PASSWORD:-admin} -s https://localhost:9200/_cluster/health > /dev/null 2>&1; then
                    echo "WARNING: OpenSearch not ready yet"
                    # Show OpenSearch logs if it's failing
                    echo "Recent OpenSearch logs:"
                    env $(cat ~/.config/lbnl-data-repository/.env | grep -v '^#' | xargs) docker-compose -f docker-compose.yml logs --tail=5 search
                    return 1
                fi
                echo "✓ OpenSearch is ready"
                ;;
            "cache")
                if ! env $(cat ~/.config/lbnl-data-repository/.env | grep -v '^#' | xargs) docker-compose -f docker-compose.yml exec -T cache redis-cli ping > /dev/null 2>&1; then
                    echo "WARNING: Redis cache not ready yet"
                    return 1
                fi
                echo "✓ Redis cache is ready"
                ;;
            "mq")
                if ! env $(cat ~/.config/lbnl-data-repository/.env | grep -v '^#' | xargs) docker-compose -f docker-compose.yml exec -T mq rabbitmq-diagnostics -q ping > /dev/null 2>&1; then
                    echo "WARNING: RabbitMQ not ready yet"
                    return 1
                fi
                echo "✓ RabbitMQ is ready"
                ;;
            "frontend")
                # Check if nginx is responding
                if ! env $(cat ~/.config/lbnl-data-repository/.env | grep -v '^#' | xargs) docker-compose -f docker-compose.yml exec -T frontend curl -k -s https://localhost:443 > /dev/null 2>&1; then
                    echo "WARNING: Frontend not ready yet"
                    echo "Recent frontend logs:"
                    env $(cat ~/.config/lbnl-data-repository/.env | grep -v '^#' | xargs) docker-compose -f docker-compose.yml logs --tail=5 frontend
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
env $(cat ~/.config/lbnl-data-repository/.env | grep -v '^#' | xargs) docker-compose -f docker-compose.yml ps

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

# Check if OPENSEARCH_ADMIN_PASSWORD is set
if [ -z "$OPENSEARCH_ADMIN_PASSWORD" ]; then
    echo "WARNING: OPENSEARCH_ADMIN_PASSWORD not set in environment"
    echo "Search container may fail to start properly"
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
        env $(cat ~/.config/lbnl-data-repository/.env | grep -v '^#' | xargs) docker-compose -f docker-compose.yml ps
        echo ""
        echo "Logs for problematic containers:"
        for service in frontend search; do
            echo "=== Logs for $service ==="
            env $(cat ~/.config/lbnl-data-repository/.env | grep -v '^#' | xargs) docker-compose -f docker-compose.yml logs --tail=30 $service
            echo ""
        done
        exit 1
    fi
    
    echo "Services not ready yet, waiting... (${elapsed}s/${timeout}s)"
    sleep $interval
    elapsed=$((elapsed + interval))
done

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