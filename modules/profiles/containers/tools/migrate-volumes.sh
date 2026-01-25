#!/usr/bin/env bash
#
# Docker Volume Migration Script
# Migrates a Docker volume from source host to destination host
# Now with automatic sudo and remote directory/volume name support
#

set -euo pipefail

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Script version
VERSION="1.0.1"

# Default values
BACKUP_DIR="/tmp/volume-migrations"
REMOTE_BACKUP_DIR="/tmp/volume-migrations"
COMPRESS="gzip"
VERIFY_CHECKSUM=true
STOP_CONTAINERS=true
AUTO_RESTART=true
REMOTE_USER=""
REMOTE_HOST=""
VOLUME_NAME=""
DEST_VOLUME_NAME=""
CONTAINER_NAME=""
SSH_PORT=22
MODE=""
USE_SUDO=""

# Function to print colored output
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if sudo is needed and set USE_SUDO variable
check_sudo() {
    if [ -z "$USE_SUDO" ]; then
        # Check if we can access docker without sudo
        if @docker@/bin/docker ps &>/dev/null; then
            USE_SUDO=""
            print_info "Docker accessible without sudo"
        else
            USE_SUDO="@sudo@/bin/sudo"
            print_info "Using sudo for Docker operations"
        fi
    fi
}

# Function to show usage
show_usage() {
    cat << EOF
Docker Volume Migration Script v${VERSION}

Usage:
  Export mode (create backup):
    $0 export -v VOLUME_NAME [-c CONTAINER_NAME] [-d BACKUP_DIR] [OPTIONS]
  
  Import mode (restore backup):
    $0 import -v VOLUME_NAME -f BACKUP_FILE [-V DEST_VOLUME] [OPTIONS]
  
  Transfer mode (export + copy to remote):
    $0 transfer -v VOLUME_NAME -r USER@HOST [-V DEST_VOLUME] [-D REMOTE_DIR] [OPTIONS]

Required Arguments:
  -v VOLUME    Source volume name to migrate
  -r USER@HOST Remote host (transfer mode only)
  -f FILE      Backup file path (import mode only)

Optional Arguments:
  -V VOLUME    Destination volume name (if different from source)
  -c CONTAINER Container name using the volume (auto-stop/start)
  -d DIR       Local backup directory (default: ${BACKUP_DIR})
  -D DIR       Remote backup directory (default: ${REMOTE_BACKUP_DIR})
  -p PORT      SSH port for remote host (default: 22)
  -n           No container stop (backup while running - may be inconsistent)
  -k           Skip checksum verification
  -z COMP      Compression: gzip, bzip2, xz, none (default: gzip)
  -h           Show this help message

Examples:
  # Export volume to local backup
  $0 export -v docker_postgres1_data -c hudu_postgres1
  
  # Import volume with different name
  $0 import -v new_postgres_data -f /tmp/volume-migrations/docker_postgres1_data.tar.gz
  
  # Transfer volume to remote host with different name and directory
  $0 transfer -v docker_postgres1_data -r admin@192.168.1.100 -V prod_postgres_data -D /backup

EOF
}

# Function to check if volume exists
check_volume_exists() {
    local volume=$1
    if ! $USE_SUDO @docker@/bin/docker volume inspect "$volume" &>/dev/null; then
        return 1
    fi
    return 0
}

# Function to get containers using a volume
get_containers_using_volume() {
    local volume=$1
    $USE_SUDO @docker@/bin/docker ps -a --filter volume="$volume" --format '{{.Names}}' | @coreutils@/bin/tr '\n' ' '
}

# Function to stop container
stop_container() {
    local container=$1
    print_info "Stopping container: $container"
    if $USE_SUDO @docker@/bin/docker stop "$container" &>/dev/null; then
        print_success "Container stopped: $container"
        return 0
    else
        print_error "Failed to stop container: $container"
        return 1
    fi
}

# Function to start container
start_container() {
    local container=$1
    print_info "Starting container: $container"
    if $USE_SUDO @docker@/bin/docker start "$container" &>/dev/null; then
        print_success "Container started: $container"
        return 0
    else
        print_error "Failed to start container: $container"
        return 1
    fi
}

# Function to get volume mountpoint
get_volume_mountpoint() {
    local volume=$1
    $USE_SUDO @docker@/bin/docker volume inspect "$volume" --format '{{.Mountpoint}}'
}

# Function to get volume size
get_volume_size() {
    local mountpoint=$1
    $USE_SUDO @coreutils@/bin/du -sh "$mountpoint" 2>/dev/null | @gawk@/bin/awk '{print $1}' || @coreutils@/bin/echo "unknown"
}

# Function to calculate checksum
calculate_checksum() {
    local file=$1
    @coreutils@/bin/sha256sum "$file" | @gawk@/bin/awk '{print $1}'
}

# Function to export volume
export_volume() {
    local volume=$1
    local backup_file=$2
    local compress_ext=""
    
    # Set compression extension
    case $COMPRESS in
        gzip)
            compress_ext=".gz"
            ;;
        bzip2)
            compress_ext=".bz2"
            ;;
        xz)
            compress_ext=".xz"
            ;;
        none)
            compress_ext=""
            ;;
        *)
            print_error "Invalid compression type: $COMPRESS"
            exit 1
            ;;
    esac
    
    backup_file="${backup_file}${compress_ext}"
    
    print_info "Exporting volume: $volume"
    print_info "Backup location: $backup_file"
    
    # Create backup using docker run with Alpine's built-in tools
    if [ "$COMPRESS" = "none" ]; then
        $USE_SUDO @docker@/bin/docker run --rm \
            -v "$volume:/volume:ro" \
            -v "$(@coreutils@/bin/dirname "$backup_file"):/backup" \
            alpine \
            tar cf "/backup/$(@coreutils@/bin/basename "$backup_file")" -C /volume .
    elif [ "$COMPRESS" = "gzip" ]; then
        $USE_SUDO @docker@/bin/docker run --rm \
            -v "$volume:/volume:ro" \
            -v "$(@coreutils@/bin/dirname "$backup_file"):/backup" \
            alpine \
            sh -c "tar cf - -C /volume . | gzip > /backup/$(@coreutils@/bin/basename "$backup_file")"
    elif [ "$COMPRESS" = "bzip2" ]; then
        $USE_SUDO @docker@/bin/docker run --rm \
            -v "$volume:/volume:ro" \
            -v "$(@coreutils@/bin/dirname "$backup_file"):/backup" \
            alpine \
            sh -c "tar cf - -C /volume . | bzip2 > /backup/$(@coreutils@/bin/basename "$backup_file")"
    elif [ "$COMPRESS" = "xz" ]; then
        $USE_SUDO @docker@/bin/docker run --rm \
            -v "$volume:/volume:ro" \
            -v "$(@coreutils@/bin/dirname "$backup_file"):/backup" \
            alpine \
            sh -c "apk add --no-cache xz > /dev/null 2>&1 && tar cf - -C /volume . | xz > /backup/$(@coreutils@/bin/basename "$backup_file")"
    fi
    
    if [ $? -eq 0 ]; then
        print_success "Volume exported successfully"
        
        # Calculate and save checksum
        if [ "$VERIFY_CHECKSUM" = true ]; then
            local checksum=$(calculate_checksum "$backup_file")
            @coreutils@/bin/echo "$checksum" > "${backup_file}.sha256"
            print_info "Checksum: $checksum"
        fi
        
        # Show backup file info
        local size=$(@coreutils@/bin/du -h "$backup_file" | @gawk@/bin/awk '{print $1}')
        print_info "Backup size: $size"
        
        return 0
    else
        print_error "Failed to export volume"
        return 1
    fi
}

# Function to import volume
import_volume() {
    local volume=$1
    local backup_file=$2
    
    print_info "Importing volume: $volume"
    print_info "Source backup: $backup_file"
    
    # Verify checksum if available
    if [ "$VERIFY_CHECKSUM" = true ] && [ -f "${backup_file}.sha256" ]; then
        print_info "Verifying checksum..."
        local expected=$(@coreutils@/bin/cat "${backup_file}.sha256")
        local actual=$(calculate_checksum "$backup_file")
        
        if [ "$expected" != "$actual" ]; then
            print_error "Checksum mismatch! File may be corrupted."
            print_error "Expected: $expected"
            print_error "Actual: $actual"
            return 1
        fi
        print_success "Checksum verified"
    fi
    
    # Create volume if it doesn't exist
    if ! check_volume_exists "$volume"; then
        print_info "Creating volume: $volume"
        $USE_SUDO @docker@/bin/docker volume create "$volume"
    fi
    
    # Import backup using Alpine's built-in tools
    if [[ "$backup_file" == *.gz ]]; then
        $USE_SUDO @docker@/bin/docker run --rm \
            -v "$volume:/volume" \
            -v "$(@coreutils@/bin/dirname "$backup_file"):/backup:ro" \
            alpine \
            sh -c "gunzip < /backup/$(@coreutils@/bin/basename "$backup_file") | tar xf - -C /volume"
    elif [[ "$backup_file" == *.bz2 ]]; then
        $USE_SUDO @docker@/bin/docker run --rm \
            -v "$volume:/volume" \
            -v "$(@coreutils@/bin/dirname "$backup_file"):/backup:ro" \
            alpine \
            sh -c "bunzip2 < /backup/$(@coreutils@/bin/basename "$backup_file") | tar xf - -C /volume"
    elif [[ "$backup_file" == *.xz ]]; then
        $USE_SUDO @docker@/bin/docker run --rm \
            -v "$volume:/volume" \
            -v "$(@coreutils@/bin/dirname "$backup_file"):/backup:ro" \
            alpine \
            sh -c "apk add --no-cache xz > /dev/null 2>&1 && unxz < /backup/$(@coreutils@/bin/basename "$backup_file") | tar xf - -C /volume"
    else
        # Uncompressed tar file
        $USE_SUDO @docker@/bin/docker run --rm \
            -v "$volume:/volume" \
            -v "$(@coreutils@/bin/dirname "$backup_file"):/backup:ro" \
            alpine \
            tar xf "/backup/$(@coreutils@/bin/basename "$backup_file")" -C /volume
    fi
    
    if [ $? -eq 0 ]; then
        print_success "Volume imported successfully"
        return 0
    else
        print_error "Failed to import volume"
        return 1
    fi
}

# Function to transfer volume to remote host
transfer_volume() {
    local volume=$1
    local remote=$2
    local ssh_port=$3
    local dest_volume="${DEST_VOLUME_NAME:-$volume}"
    local remote_dir="${REMOTE_BACKUP_DIR}"
    
    print_info "Transferring volume: $volume"
    print_info "Destination: $remote"
    if [ "$dest_volume" != "$volume" ]; then
        print_info "Destination volume name: $dest_volume"
    fi
    print_info "Remote directory: $remote_dir"
    
    # First, export the volume
    local backup_file="${BACKUP_DIR}/${volume}.tar"
    @coreutils@/bin/mkdir -p "$BACKUP_DIR"
    
    if ! export_volume "$volume" "$backup_file"; then
        return 1
    fi
    
    # Get the actual backup filename (with compression extension)
    local compress_ext=""
    case $COMPRESS in
        gzip) compress_ext=".gz" ;;
        bzip2) compress_ext=".bz2" ;;
        xz) compress_ext=".xz" ;;
    esac
    backup_file="${backup_file}${compress_ext}"
    local backup_filename=$(@coreutils@/bin/basename "$backup_file")
    
    # Transfer to remote host
    print_info "Transferring backup to remote host..."
    
    # Create remote directory (try with sudo first, then without)
    @openssh@/bin/ssh -p "$ssh_port" "$remote" "sudo mkdir -p $remote_dir && sudo chmod 755 $remote_dir" 2>/dev/null || \
        @openssh@/bin/ssh -p "$ssh_port" "$remote" "mkdir -p $remote_dir" || {
            print_error "Failed to create remote directory"
            return 1
        }
    
    # Transfer backup file to temporary location first
    local temp_dir="/tmp/volume-migration-$$"
    @openssh@/bin/ssh -p "$ssh_port" "$remote" "mkdir -p $temp_dir" || {
        print_error "Failed to create temporary directory on remote host"
        return 1
    }
    
    @openssh@/bin/scp -P "$ssh_port" "$backup_file" "${remote}:${temp_dir}/${backup_filename}" || {
        print_error "Failed to transfer backup file"
        @openssh@/bin/ssh -p "$ssh_port" "$remote" "rm -rf $temp_dir" 2>/dev/null
        return 1
    }
    
    # Transfer checksum if exists
    if [ -f "${backup_file}.sha256" ]; then
        @openssh@/bin/scp -P "$ssh_port" "${backup_file}.sha256" "${remote}:${temp_dir}/${backup_filename}.sha256" || {
            print_warning "Failed to transfer checksum file"
        }
    fi
    
    # Move files to final destination with sudo (try sudo first, then without)
    print_info "Moving files to final destination with sudo..."
    @openssh@/bin/ssh -p "$ssh_port" "$remote" "sudo mv $temp_dir/${backup_filename} ${remote_dir}/ && sudo chmod 644 ${remote_dir}/${backup_filename}" 2>/dev/null || \
        @openssh@/bin/ssh -p "$ssh_port" "$remote" "mv $temp_dir/${backup_filename} ${remote_dir}/" || {
            print_error "Failed to move backup file to destination"
            @openssh@/bin/ssh -p "$ssh_port" "$remote" "rm -rf $temp_dir" 2>/dev/null
            return 1
        }
    
    # Move checksum file if exists
    if [ -f "${backup_file}.sha256" ]; then
        @openssh@/bin/ssh -p "$ssh_port" "$remote" "sudo mv $temp_dir/${backup_filename}.sha256 ${remote_dir}/ && sudo chmod 644 ${remote_dir}/${backup_filename}.sha256" 2>/dev/null || \
            @openssh@/bin/ssh -p "$ssh_port" "$remote" "mv $temp_dir/${backup_filename}.sha256 ${remote_dir}/" 2>/dev/null
    fi
    
    # Clean up temporary directory
    @openssh@/bin/ssh -p "$ssh_port" "$remote" "rm -rf $temp_dir" 2>/dev/null
    
    print_success "Transfer completed"
    print_info "To import on remote host, run:"
    print_info "  ./migrate-volume.sh import -v $dest_volume -f ${remote_dir}/${backup_filename}"
    
    return 0
}

# Parse command line arguments
if [ $# -eq 0 ]; then
    show_usage
    exit 1
fi

# Check for help flag first
if [[ "$1" == "-h" ]] || [[ "$1" == "--help" ]]; then
    show_usage
    exit 0
fi

MODE=$1
shift

while getopts "v:V:c:d:D:r:f:p:z:nkh" opt; do
    case $opt in
        v) VOLUME_NAME="$OPTARG" ;;
        V) DEST_VOLUME_NAME="$OPTARG" ;;
        c) CONTAINER_NAME="$OPTARG" ;;
        d) BACKUP_DIR="$OPTARG" ;;
        D) REMOTE_BACKUP_DIR="$OPTARG" ;;
        r) 
            REMOTE_USER="${OPTARG%%@*}"
            REMOTE_HOST="${OPTARG#*@}"
            ;;
        f) BACKUP_FILE="$OPTARG" ;;
        p) SSH_PORT="$OPTARG" ;;
        z) COMPRESS="$OPTARG" ;;
        n) STOP_CONTAINERS=false ;;
        k) VERIFY_CHECKSUM=false ;;
        h) show_usage; exit 0 ;;
        \?) print_error "Invalid option: -$OPTARG"; show_usage; exit 1 ;;
    esac
done

# Validate mode
if [[ ! "$MODE" =~ ^(export|import|transfer)$ ]]; then
    print_error "Invalid mode: $MODE"
    show_usage
    exit 1
fi

# Validate required arguments
if [ -z "$VOLUME_NAME" ]; then
    print_error "Volume name is required (-v)"
    show_usage
    exit 1
fi

if [ "$MODE" = "transfer" ] && [ -z "$REMOTE_HOST" ]; then
    print_error "Remote host is required for transfer mode (-r)"
    show_usage
    exit 1
fi

if [ "$MODE" = "import" ] && [ -z "$BACKUP_FILE" ]; then
    print_error "Backup file is required for import mode (-f)"
    show_usage
    exit 1
fi

# Main execution
check_sudo
print_info "=== Docker Volume Migration Tool v${VERSION} ==="
print_info "Mode: $MODE"
print_info "Volume: $VOLUME_NAME"
if [ -n "$DEST_VOLUME_NAME" ]; then
    print_info "Destination Volume: $DEST_VOLUME_NAME"
fi

case $MODE in
    export)
        # Check if volume exists
        if ! check_volume_exists "$VOLUME_NAME"; then
            print_error "Volume does not exist: $VOLUME_NAME"
            exit 1
        fi
        
        # Show volume info
        mountpoint=$(get_volume_mountpoint "$VOLUME_NAME")
        size=$(get_volume_size "$mountpoint")
        print_info "Volume size: $size"
        
        # Get containers using volume
        containers=$(get_containers_using_volume "$VOLUME_NAME")
        if [ -n "$containers" ]; then
            print_info "Containers using this volume: $containers"
        fi
        
        # Determine container to stop
        if [ -n "$CONTAINER_NAME" ]; then
            containers_to_stop="$CONTAINER_NAME"
        elif [ "$STOP_CONTAINERS" = true ] && [ -n "$containers" ]; then
            containers_to_stop="$containers"
        else
            containers_to_stop=""
        fi
        
        # Stop containers if needed
        stopped_containers=""
        if [ -n "$containers_to_stop" ] && [ "$STOP_CONTAINERS" = true ]; then
            for container in $containers_to_stop; do
                if $USE_SUDO @docker@/bin/docker ps --format '{{.Names}}' | @gnugrep@/bin/grep -q "^${container}$"; then
                    if stop_container "$container"; then
                        stopped_containers="$stopped_containers $container"
                    fi
                fi
            done
        else
            print_warning "Backing up volume without stopping containers - data may be inconsistent"
        fi
        
        # Create backup directory
        @coreutils@/bin/mkdir -p "$BACKUP_DIR"
        
        # Export volume
        backup_file="${BACKUP_DIR}/${VOLUME_NAME}.tar"
        export_volume "$VOLUME_NAME" "$backup_file"
        result=$?
        
        # Restart containers
        if [ -n "$stopped_containers" ] && [ "$AUTO_RESTART" = true ]; then
            for container in $stopped_containers; do
                start_container "$container"
            done
        fi
        
        exit $result
        ;;
        
    import)
        # Check if backup file exists
        if [ ! -f "$BACKUP_FILE" ]; then
            print_error "Backup file does not exist: $BACKUP_FILE"
            exit 1
        fi
        
        # Use destination volume name if specified, otherwise use source
        import_volume_name="${DEST_VOLUME_NAME:-$VOLUME_NAME}"
        
        # Get containers using volume if it exists
        containers=""
        if check_volume_exists "$import_volume_name"; then
            containers=$(get_containers_using_volume "$import_volume_name")
            if [ -n "$containers" ]; then
                print_warning "The following containers use this volume: $containers"
                print_warning "Consider stopping them before importing"
            fi
        fi
        
        # Determine container to stop
        if [ -n "$CONTAINER_NAME" ]; then
            containers_to_stop="$CONTAINER_NAME"
        elif [ "$STOP_CONTAINERS" = true ] && [ -n "$containers" ]; then
            containers_to_stop="$containers"
        else
            containers_to_stop=""
        fi
        
        # Stop containers if needed
        stopped_containers=""
        if [ -n "$containers_to_stop" ] && [ "$STOP_CONTAINERS" = true ]; then
            for container in $containers_to_stop; do
                if $USE_SUDO @docker@/bin/docker ps --format '{{.Names}}' | @gnugrep@/bin/grep -q "^${container}$"; then
                    if stop_container "$container"; then
                        stopped_containers="$stopped_containers $container"
                    fi
                fi
            done
        fi
        
        # Import volume (use destination name if specified)
        import_volume "$import_volume_name" "$BACKUP_FILE"
        result=$?
        
        # Restart containers
        if [ -n "$stopped_containers" ] && [ "$AUTO_RESTART" = true ]; then
            for container in $stopped_containers; do
                start_container "$container"
            done
        fi
        
        exit $result
        ;;
        
    transfer)
        # Check if volume exists
        if ! check_volume_exists "$VOLUME_NAME"; then
            print_error "Volume does not exist: $VOLUME_NAME"
            exit 1
        fi
        
        # Show volume info
        mountpoint=$(get_volume_mountpoint "$VOLUME_NAME")
        size=$(get_volume_size "$mountpoint")
        print_info "Volume size: $size"
        
        # Get containers using volume
        containers=$(get_containers_using_volume "$VOLUME_NAME")
        if [ -n "$containers" ]; then
            print_info "Containers using this volume: $containers"
        fi
        
        # Determine container to stop
        if [ -n "$CONTAINER_NAME" ]; then
            containers_to_stop="$CONTAINER_NAME"
        elif [ "$STOP_CONTAINERS" = true ] && [ -n "$containers" ]; then
            containers_to_stop="$containers"
        else
            containers_to_stop=""
        fi
        
        # Stop containers if needed
        stopped_containers=""
        if [ -n "$containers_to_stop" ] && [ "$STOP_CONTAINERS" = true ]; then
            for container in $containers_to_stop; do
                if $USE_SUDO @docker@/bin/docker ps --format '{{.Names}}' | @gnugrep@/bin/grep -q "^${container}$"; then
                    if stop_container "$container"; then
                        stopped_containers="$stopped_containers $container"
                    fi
                fi
            done
        else
            print_warning "Transferring volume without stopping containers - data may be inconsistent"
        fi
        
        # Transfer volume
        transfer_volume "$VOLUME_NAME" "${REMOTE_USER}@${REMOTE_HOST}" "$SSH_PORT"
        result=$?
        
        # Restart containers
        if [ -n "$stopped_containers" ] && [ "$AUTO_RESTART" = true ]; then
            for container in $stopped_containers; do
                start_container "$container"
            done
        fi
        
        exit $result
        ;;
esac
