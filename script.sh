#!/bin/bash

# Dokploy Health Check & Recovery Script
# Automates common troubleshooting steps for Dokploy UI accessibility issues

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Required containers
REQUIRED_CONTAINERS=("dokploy" "dokploy-postgres" "dokploy-redis" "dokploy-traefik")

print_header() {
    echo -e "${BLUE}=================================${NC}"
    echo -e "${BLUE}  Dokploy Health Check & Recovery${NC}"
    echo -e "${BLUE}=================================${NC}"
    echo ""
}

print_step() {
    echo -e "${YELLOW}>>> $1${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

check_docker() {
    print_step "Checking Docker availability..."
    if ! command -v docker &> /dev/null; then
        print_error "Docker is not installed or not in PATH"
        exit 1
    fi
    print_success "Docker is available"
}

check_disk_space() {
    print_step "Checking disk space..."
    
    # Get available space in GB
    AVAILABLE_SPACE=$(df / | awk 'NR==2 {print int($4/1024/1024)}')
    
    if [ "$AVAILABLE_SPACE" -lt 2 ]; then
        print_error "Low disk space detected (${AVAILABLE_SPACE}GB available)"
        read -p "Run Docker cleanup to free space? (y/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            cleanup_docker
        else
            print_info "Skipping cleanup. Consider freeing disk space manually."
        fi
    else
        print_success "Sufficient disk space available (${AVAILABLE_SPACE}GB)"
    fi
}

cleanup_docker() {
    print_step "Cleaning up Docker resources..."
    
    echo "Pruning Docker system..."
    docker system prune -a -f
    
    echo "Pruning Docker builder cache..."
    docker builder prune -a -f
    
    echo "Pruning unused images..."
    docker image prune -a -f
    
    print_success "Docker cleanup completed"
}

check_containers() {
    print_step "Checking container status..."
    
    local missing_containers=()
    local unhealthy_containers=()
    
    for container in "${REQUIRED_CONTAINERS[@]}"; do
        if docker service ls --filter name="$container" --format "{{.Name}}" | grep -q "^$container$"; then
            # Check if service is running
            REPLICAS=$(docker service ls --filter name="$container" --format "{{.Replicas}}")
            if [[ $REPLICAS == "1/1" ]]; then
                print_success "$container service is running"
            else
                print_error "$container service is not healthy ($REPLICAS)"
                unhealthy_containers+=("$container")
            fi
        elif docker ps --filter name="$container" --format "{{.Names}}" | grep -q "^dokploy-$container"; then
            # Check standalone container
            print_success "$container container is running"
        else
            print_error "$container is not running"
            missing_containers+=("$container")
        fi
    done
    
    return $((${#missing_containers[@]} + ${#unhealthy_containers[@]}))
}

check_logs() {
    print_step "Checking container logs for common issues..."
    
    # Check Dokploy logs for database connection issues
    if docker service logs dokploy 2>/dev/null | grep -q "ENOTFOUND dokploy-postgres"; then
        print_error "Database connection issue detected in Dokploy logs"
        return 1
    fi
    
    # Check Traefik logs for configuration issues
    if docker logs dokploy-traefik 2>/dev/null | grep -q "field not found\|Error occurred during watcher callback"; then
        print_error "Traefik configuration issues detected"
        return 2
    fi
    
    print_success "No obvious issues found in logs"
    return 0
}

fix_database_connection() {
    print_step "Fixing database connection issue..."
    
    echo "Scaling Dokploy service to 0..."
    docker service scale dokploy=0
    
    echo "Waiting for service to stop..."
    sleep 5
    
    echo "Scaling Dokploy service back to 1..."
    docker service scale dokploy=1
    
    echo "Waiting for service to start..."
    sleep 10
    
    print_success "Dokploy service restarted"
}

fix_traefik_config() {
    print_step "Fixing Traefik configuration..."
    
    echo "Restarting Traefik container..."
    if docker service ls --filter name="dokploy-traefik" --format "{{.Name}}" | grep -q "dokploy-traefik"; then
        docker service update --force dokploy-traefik
    else
        docker restart dokploy-traefik
    fi
    
    echo "Waiting for Traefik to restart..."
    sleep 5
    
    print_success "Traefik restarted"
}

test_ui_access() {
    print_step "Testing UI accessibility..."
    
    # Try to access localhost:3000
    if curl -s -o /dev/null -w "%{http_code}" http://localhost:3000 | grep -q "200\|302\|301"; then
        print_success "Dokploy UI is accessible on http://localhost:3000"
        return 0
    else
        print_error "Dokploy UI is not accessible on http://localhost:3000"
        return 1
    fi
}

show_status() {
    print_step "Current system status:"
    echo ""
    echo "Running containers/services:"
    docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep -E "(dokploy|traefik|postgres|redis)"
    echo ""
    docker service ls 2>/dev/null | grep dokploy || echo "No Dokploy services found"
}

interactive_mode() {
    while true; do
        echo ""
        echo "Choose an action:"
        echo "1) Full health check and auto-repair"
        echo "2) Check container status only"
        echo "3) Clean up Docker resources"
        echo "4) Restart Dokploy service"
        echo "5) Restart Traefik"
        echo "6) Show current status"
        echo "7) Test UI access"
        echo "8) Exit"
        echo ""
        read -p "Enter choice (1-8): " choice
        
        case $choice in
            1)
                run_full_check
                ;;
            2)
                check_containers
                ;;
            3)
                cleanup_docker
                ;;
            4)
                fix_database_connection
                ;;
            5)
                fix_traefik_config
                ;;
            6)
                show_status
                ;;
            7)
                test_ui_access
                ;;
            8)
                echo "Goodbye!"
                exit 0
                ;;
            *)
                print_error "Invalid choice. Please try again."
                ;;
        esac
    done
}

run_full_check() {
    print_header
    
    check_docker
    check_disk_space
    
    if ! check_containers; then
        print_info "Some containers are not running properly"
    fi
    
    LOG_CHECK_RESULT=$(check_logs; echo $?)
    
    case $LOG_CHECK_RESULT in
        1)
            print_info "Attempting to fix database connection..."
            fix_database_connection
            ;;
        2)
            print_info "Attempting to fix Traefik configuration..."
            fix_traefik_config
            ;;
    esac
    
    echo ""
    print_step "Final verification..."
    sleep 5
    
    if test_ui_access; then
        print_success "Dokploy recovery completed successfully!"
    else
        print_error "UI still not accessible. Manual intervention may be required."
        echo ""
        print_info "Try accessing these URLs:"
        echo "  - http://localhost:3000"
        echo "  - http://$(hostname -I | awk '{print $1}'):3000"
        echo ""
        print_info "Check logs manually:"
        echo "  docker service logs dokploy"
        echo "  docker logs dokploy-traefik"
    fi
}

# Main execution
if [[ $# -eq 0 ]]; then
    run_full_check
    echo ""
    read -p "Would you like to enter interactive mode? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        interactive_mode
    fi
else
    case "$1" in
        --check-only)
            check_containers
            ;;
        --cleanup)
            cleanup_docker
            ;;
        --interactive)
            interactive_mode
            ;;
        --help)
            echo "Dokploy Health Check & Recovery Script"
            echo ""
            echo "Usage: $0 [option]"
            echo ""
            echo "Options:"
            echo "  --check-only    Only check container status"
            echo "  --cleanup       Only run Docker cleanup"
            echo "  --interactive   Enter interactive mode"
            echo "  --help          Show this help message"
            echo ""
            echo "Run without arguments for full auto-recovery"
            ;;
        *)
            print_error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
fi