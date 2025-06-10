#!/bin/bash
set -e

# Default values
DEBUG_MODE=false
INVENIO_PORT=5002

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
            shift 2
            ;;
        --help)
            echo "Usage: $0 [--debug] [--port <port>]"
            echo "  --debug: Start containers only (for debugging)"
            echo "  --port:  Specify InvenioRDM port (default: 5002)"
            exit 0
            ;;
        *)
            echo "❌ ERROR: Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Error handling setup
set -o pipefail  # Exit on pipe failures

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
    fi
}

trap cleanup_on_error EXIT

# Validation functions
validate_environment() {
    echo "🔍 Validating environment setup..."
    
    # Check .env file exists and is readable
    if [ ! -f ~/.config/lbnl-data-repository/.env ]; then
        echo "❌ ERROR: Environment file not found at ~/.config/lbnl-data-repository/.env"
        echo "Please create the environment file with required variables."
        exit 1
    fi
    
    if [ ! -r ~/.config/lbnl-data-repository/.env ]; then
        echo "❌ ERROR: Environment file is not readable: ~/.config/lbnl-data-repository/.env"
        echo "Please check file permissions."
        exit 1
    fi
    
    # Check if OPENSEARCH_ADMIN_PASSWORD is set and not empty in .env file
    if ! grep -q "^OPENSEARCH_ADMIN_PASSWORD=..*" ~/.config/lbnl-data-repository/.env; then
        echo "❌ ERROR: OPENSEARCH_ADMIN_PASSWORD not set or empty in environment file"
        echo "Please set a strong password for OpenSearch admin user."
        exit 1
    fi
    
    echo "✅ Environment file validation passed"
}

validate_ssl_certificates() {
    echo "🔍 Validating SSL certificates..."
    
    local cert_dir="$HOME/.config/lbnl-data-repository/ssl"
    local required_files=(
        "server.pem"
        "server-key.pem"
        "ca.pem"
    )
    
    for file in "${required_files[@]}"; do
        local file_path="$cert_dir/$file"
        if [ ! -f "$file_path" ]; then
            echo "❌ ERROR: SSL certificate not found: $file_path"
            echo "Please run generate-certs.sh to create required certificates."
            exit 1
        fi
        
        if [ ! -r "$file_path" ]; then
            echo "❌ ERROR: SSL certificate not readable: $file_path"
            echo "Please check file permissions."
            exit 1
        fi
    done
    
    echo "✅ SSL certificate validation passed"
}

validate_port() {
    local port=$1
    
    if ! [[ "$port" =~ ^[0-9]+$ ]] || [ "$port" -lt 1024 ] || [ "$port" -gt 65535 ]; then
        echo "❌ ERROR: Invalid port number: $port"
        echo "Port must be a number between 1024 and 65535."
        exit 1
    fi
    
    # Check if port is already in use
    if lsof -i ":$port" >/dev/null 2>&1; then
        echo "❌ ERROR: Port $port is already in use"
        echo "Please choose a different port or stop the service using that port."
        exit 1
    fi
    
    echo "✅ Port $port is available"
}

# Logging functions with prefixes
log_with_prefix() {
    local prefix=$1
    local message=$2
    echo "[$prefix] $message"
}

log_search() { log_with_prefix "search" "$1"; }
log_db() { log_with_prefix "db" "$1"; }
log_cache() { log_with_prefix "cache" "$1"; }
log_mq() { log_with_prefix "mq" "$1"; }
log_invenio() { log_with_prefix "invenio" "$1"; }
log_frontend() { log_with_prefix "frontend" "$1"; }
log_pgadmin() { log_with_prefix "pgadmin" "$1"; }
log_dashboards() { log_with_prefix "opensearch-dashboards" "$1"; }

start_invenio_rdm() {
    local port=$1
    echo "🚀 Starting InvenioRDM on port $port..."
    
    # Start InvenioRDM with proper environment variables in background
    env $(cat ~/.config/lbnl-data-repository/.env | grep -v '^#' | xargs) \
        nohup invenio run --host 127.0.0.1 --port "$port" > invenio.log 2>&1 &
    
    local invenio_pid=$!
    echo "$invenio_pid" > invenio.pid
    log_invenio "Started with PID: $invenio_pid"
    
    # Wait for InvenioRDM to start up
    log_invenio "Waiting for initialization..."
    local timeout=120
    local elapsed=0
    local interval=3
    
    while [ $elapsed -lt $timeout ]; do
        if kill -0 "$invenio_pid" 2>/dev/null; then
            if curl -s -f "http://127.0.0.1:$port" >/dev/null 2>&1; then
                log_invenio "Service is responding on port $port"
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
        log_invenio "Still initializing... (${elapsed}s/${timeout}s)"
    done
    
    echo "❌ ERROR: InvenioRDM failed to start within ${timeout} seconds"
    if kill -0 "$invenio_pid" 2>/dev/null; then
        echo "Process is still running but not responding to HTTP requests."
        echo "Recent InvenioRDM logs:"
        tail -20 invenio.log
    fi
    return 1
}

check_invenio_backend_connectivity() {
    echo "🔍 Verifying InvenioRDM backend service connectivity..."
    
    # Test OpenSearch connectivity
    if env $(cat ~/.config/lbnl-data-repository/.env | grep -v '^#' | xargs) \
        docker-compose -f docker-compose.yml exec -T search \
        curl -k -u admin:${OPENSEARCH_ADMIN_PASSWORD} -s https://localhost:9200/_cluster/health >/dev/null 2>&1; then
        log_invenio "OpenSearch connectivity verified"
    else
        echo "❌ ERROR: InvenioRDM cannot connect to OpenSearch"
        echo "Check OpenSearch service status and credentials."
        return 1
    fi
    
    # Test PostgreSQL connectivity
    if env $(cat ~/.config/lbnl-data-repository/.env | grep -v '^#' | xargs) \
        docker-compose -f docker-compose.yml exec -T db \
        pg_isready -U lbnl-data-repository >/dev/null 2>&1; then
        log_invenio "PostgreSQL connectivity verified"
    else
        echo "❌ ERROR: InvenioRDM cannot connect to PostgreSQL"
        echo "Check database service status."
        return 1
    fi
    
    # Test Redis connectivity
    if env $(cat ~/.config/lbnl-data-repository/.env | grep -v '^#' | xargs) \
        docker-compose -f docker-compose.yml exec -T cache \
        redis-cli ping >/dev/null 2>&1; then
        log_invenio "Redis connectivity verified"
    else
        echo "❌ ERROR: InvenioRDM cannot connect to Redis"
        echo "Check Redis service status."
        return 1
    fi
    
    # Test RabbitMQ connectivity
    if env $(cat ~/.config/lbnl-data-repository/.env | grep -v '^#' | xargs) \
        docker-compose -f docker-compose.yml exec -T mq \
        rabbitmq-diagnostics -q ping >/dev/null 2>&1; then
        log_invenio "RabbitMQ connectivity verified"
    else
        echo "❌ ERROR: InvenioRDM cannot connect to RabbitMQ"
        echo "Check RabbitMQ service status."
        return 1
    fi
    
    return 0
}

display_success_summary() {
    local invenio_port=$1
    
    # Load environment to get password for display
    source ~/.config/lbnl-data-repository/.env
    
    echo ""
    echo "🎉 =================================================="
    echo "✅           ALL SERVICES READY!"
    echo "🎉 =================================================="
    echo ""
    echo "🌐 Service URLs:"
    echo "   • InvenioRDM:             http://127.0.0.1:$invenio_port"
    echo "   • OpenSearch Dashboards:  https://127.0.0.1:5601"
    echo "   • PgAdmin:                http://127.0.0.1:5050"
    echo "   • RabbitMQ Management:    http://127.0.0.1:15672"
    echo ""
    echo "🔑 Credentials:"
    echo "   • OpenSearch:  admin / (from environment)"
    echo "   • PgAdmin:     tyfong@lbl.gov / lbnl-data-repository"
    echo "   • RabbitMQ:    guest / guest"
    echo ""
    echo "🛠️  Management Commands:"
    echo "   • Check status:    docker-compose -f docker-compose.yml ps"
    echo "   • View logs:       docker-compose -f docker-compose.yml logs -f <service>"
    echo "   • Stop containers: docker-compose -f docker-compose.yml down"
    echo "   • Stop InvenioRDM: kill \$(cat invenio.pid) && rm -f invenio.pid"
    echo ""
    echo "📋 Available services: search, db, cache, mq, frontend, pgadmin, opensearch-dashboards"
    echo ""
    echo "🚀 Your development environment is ready!"
    echo "=================================================="
}

check_services_ready() {
    echo "Checking if all services are ready..."

    local services=("search" "db" "cache" "mq" "frontend" "pgadmin" "opensearch-dashboards")
    for service in "${services[@]}"; do
        local container_status=$(docker-compose -f docker-compose.yml inspect -f '{{.State.Status}}' "$service")
        local container_running=$(docker-compose -f docker-compose.yml inspect -f '{{.State.Running}}' "$service")
        local restart_count=$(docker-compose -f docker-compose.yml inspect -f '{{.RestartCount}}' "$service")

        log_with_prefix "$service" "Status=$container_status, Running=$container_running, Restarts=$restart_count"

        if [ "$container_status" != "running" ] || [ "$container_running" != "true" ]; then
            echo "❌ Service $service is not running"
            return 1
        fi
    done

    log_db "Database is ready"
    log_search "OpenSearch is ready"
    log_cache "Redis cache is ready"
    log_mq "RabbitMQ is ready"
    log_frontend "Frontend is ready"

    echo "All services are ready!"
    return 0
}

# Main execution flow based on mode
echo ""
echo "🔧 LBNL Data Repository - Enhanced Service Startup"
echo "=================================================="

# Phase 1: Pre-flight validation
validate_environment
validate_ssl_certificates

if [ "$DEBUG_MODE" = false ]; then
    validate_port "$INVENIO_PORT"
    echo "🚀 Starting in FULL mode (containers + InvenioRDM)"
else
    echo "🔧 Starting in DEBUG mode (containers only)"
fi

echo ""

# Phase 2: Container startup and health checks (existing logic runs here)
if ! check_services_ready; then
    echo "❌ Container startup failed"
    exit 1
fi

# Phase 3: InvenioRDM startup (if not in debug mode)
if [ "$DEBUG_MODE" = false ]; then
    echo ""
    if start_invenio_rdm "$INVENIO_PORT"; then
        if check_invenio_backend_connectivity; then
            display_success_summary "$INVENIO_PORT"
        else
            echo "❌ Backend connectivity check failed"
            exit 1
        fi
    else
        echo "❌ InvenioRDM startup failed"
        exit 1
    fi
else
    echo ""
    echo "🔧 Debug mode: Containers started successfully"
    echo "   • Use 'docker-compose -f docker-compose.yml ps' to check status"
    echo "   • Use 'docker-compose -f docker-compose.yml logs -f <service>' to view logs"
    echo "   • To start InvenioRDM manually:"
    echo "     env \$(cat ~/.config/lbnl-data-repository/.env | grep -v '^#' | xargs) invenio run --host 127.0.0.1 --port $INVENIO_PORT"
fi

