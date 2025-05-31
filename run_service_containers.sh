#!/bin/bash
set -e  # Exit on any error

# Load environment variables from external .env
if [ -f ~/.config/lbnl-data-repository/.env ]; then
    export $(egrep -v '^#' ~/.config/lbnl-data-repository/.env | xargs)
    echo "Loaded environment variables from ~/.config/lbnl-data-repository/.env"
else
    echo "Warning: Environment file ~/.config/lbnl-data-repository/.env not found"
    echo "Some services may not work correctly without proper environment variables"
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
        container_status=$(env $(cat ~/.config/lbnl-data-repository/.env | grep -v '^#' | xargs) docker-compose -f docker-compose.yml ps -q $service | xargs docker inspect -K        container_running=$(env $(cat ~/.config/lbnl-data-repository/.env | grep -v '^#' | xargs) docker-compose -f docker-compose.yml ps -q $service | xargs docker inspect -f '{{.State.Running}}' 2>/dev/null || echo "false")
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
echo "All services are ready!"

echo "You can view service logs with: docker-compose -f docker-compose.yml logs -f"





