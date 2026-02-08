#!/usr/bin/env bash
#
# Docker Volume Migration Script
# Migrates Docker volumes between hosts using the dedicated docker user.
#
# The docker user has Docker socket access via group membership (no sudo needed)
# and SSH keys are managed through the secrets module + systemd deployment.
#

set -euo pipefail

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Script version
VERSION="3.0.0"

# Default values
BACKUP_DIR="/var/lib/docker/volumes/.migration-staging"
COMPRESS="gzip"
VERIFY_CHECKSUM=true
STOP_CONTAINERS=true
AUTO_RESTART=true
REMOTE_HOST=""
VOLUME_NAME=""
DEST_VOLUME_NAME=""
CONTAINER_NAME=""
REMOTE_CONTAINER_NAME=""
SSH_PORT=22
MODE=""
BACKUP_FILE=""

# SSH key for docker user volume migration
SSH_KEY="/home/docker/.ssh/volume-migration-key"
REMOTE_USER="docker"

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

# Function to verify docker access
check_docker_access() {
    if ! @docker@/bin/docker ps &>/dev/null; then
        print_error "Cannot access Docker. Ensure this script is run by a user in the docker group."
        exit 1
    fi
    print_info "Docker access verified"
}

# Function to verify SSH key exists for remote operations
check_ssh_key() {
    if [ ! -f "$SSH_KEY" ] && ! /run/wrappers/bin/sudo -u "$REMOTE_USER" test -f "$SSH_KEY" 2>/dev/null; then
        print_error "SSH key not found at $SSH_KEY"
        print_error "Ensure the volumeMigration secret is configured and the deploy-docker-migration-key service has run."
        exit 1
    fi
}

# Function to run SSH command on remote host (as docker user)
remote_ssh() {
    /run/wrappers/bin/sudo -u "$REMOTE_USER" @openssh@/bin/ssh -p "$SSH_PORT" "${REMOTE_USER}@${REMOTE_HOST}" "$@"
}

# Function to show usage
show_usage() {
    cat << EOF
Docker Volume Migration Script v${VERSION}

Usage:
  Export mode (create local backup):
    $0 export -v VOLUME_NAME [-c CONTAINER_NAME] [-d BACKUP_DIR] [OPTIONS]
  
  Import mode (restore from local backup):
    $0 import -v VOLUME_NAME -f BACKUP_FILE [-V DEST_VOLUME] [OPTIONS]
  
  Transfer mode (direct transfer to remote host):
    $0 transfer -v VOLUME_NAME -r HOST [-V DEST_VOLUME] [-c LOCAL_CONTAINER] [-C REMOTE_CONTAINER] [OPTIONS]

Required Arguments:
  -v VOLUME    Source volume name to migrate
  -r HOST      Remote host IP/hostname (transfer mode only, connects as docker user)
  -f FILE      Backup file path (import mode only)

Optional Arguments:
  -V VOLUME    Destination volume name on remote (if different from source)
  -c CONTAINER Container name using the volume locally (auto-stop/start)
  -C CONTAINER Container name on remote host to stop/start during transfer
  -d DIR       Local backup directory (default: ${BACKUP_DIR})
  -p PORT      SSH port for remote host (default: 22)
  -n           No container stop (backup while running - may be inconsistent)
  -k           Skip checksum verification
  -z COMP      Compression: gzip, bzip2, xz, none (default: gzip)
  -h           Show this help message

Notes:
  - Export/import use ${BACKUP_DIR} (inside Docker's data dir).
  - Transfer mode streams data directly into the remote volume via SSH.
    No intermediate files are created on either host during transfer.
  - Transfer mode auto-detects and stops containers on both local and remote hosts.
  - After transfer, local containers are NOT restarted (volume has moved).
  - The docker user's SSH key is managed through the secrets module.

Examples:
  # Export volume to local backup
  $0 export -v docker_postgres1_data -c hudu_postgres1
  
  # Import volume from backup
  $0 import -v docker_postgres1_data -f ${BACKUP_DIR}/docker_postgres1_data.tar.gz
  
  # Transfer volume to remote host (auto-discovers containers)
  $0 transfer -v docker_postgres1_data -r 10.1.11.3

  # Transfer with different destination name and explicit remote container
  $0 transfer -v docker_postgres1_data -r 10.1.11.3 -V prod_postgres_data -C hudu_postgres1

EOF
}

# Function to check if volume exists
check_volume_exists() {
    local volume=$1
    @docker@/bin/docker volume inspect "$volume" &>/dev/null
}

# Function to get containers using a volume (all, including stopped)
get_containers_using_volume() {
    local volume=$1
    @docker@/bin/docker ps -a --filter volume="$volume" --format '{{.Names}}' | @coreutils@/bin/tr '\n' ' '
}

# Function to get running containers using a volume
get_running_containers_using_volume() {
    local volume=$1
    @docker@/bin/docker ps --filter volume="$volume" --format '{{.Names}}' | @coreutils@/bin/tr '\n' ' '
}

# Function to stop container
stop_container() {
    local container=$1
    print_info "Stopping container: $container"
    if @docker@/bin/docker stop "$container" &>/dev/null; then
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
    if @docker@/bin/docker start "$container" &>/dev/null; then
        print_success "Container started: $container"
        return 0
    else
        print_error "Failed to start container: $container"
        return 1
    fi
}

# Function to stop a container on a remote host
remote_stop_container() {
    local container=$1
    print_info "Stopping remote container: $container"
    if remote_ssh "docker stop $container" &>/dev/null; then
        print_success "Remote container stopped: $container"
        return 0
    else
        print_error "Failed to stop remote container: $container"
        return 1
    fi
}

# Function to start a container on a remote host
remote_start_container() {
    local container=$1
    print_info "Starting remote container: $container"
    if remote_ssh "docker start $container" &>/dev/null; then
        print_success "Remote container started: $container"
        return 0
    else
        print_error "Failed to start remote container: $container"
        return 1
    fi
}

# Function to get volume mountpoint
get_volume_mountpoint() {
    local volume=$1
    @docker@/bin/docker volume inspect "$volume" --format '{{.Mountpoint}}'
}

# Function to get volume size
get_volume_size() {
    local mountpoint=$1
    @coreutils@/bin/du -sh "$mountpoint" 2>/dev/null | @gawk@/bin/awk '{print $1}' || @coreutils@/bin/echo "unknown"
}

# Function to calculate checksum
calculate_checksum() {
    local file=$1
    @coreutils@/bin/sha256sum "$file" | @gawk@/bin/awk '{print $1}'
}

# Function to get compression command
get_compress_cmd() {
    case $COMPRESS in
        gzip)  echo "gzip" ;;
        bzip2) echo "bzip2" ;;
        xz)    echo "xz" ;;
        none)  echo "cat" ;;
    esac
}

# Function to get decompression command
get_decompress_cmd() {
    case $COMPRESS in
        gzip)  echo "gunzip" ;;
        bzip2) echo "bunzip2" ;;
        xz)    echo "unxz" ;;
        none)  echo "cat" ;;
    esac
}

# Function to get compression file extension
get_compress_ext() {
    case $COMPRESS in
        gzip)  echo ".gz" ;;
        bzip2) echo ".bz2" ;;
        xz)    echo ".xz" ;;
        none)  echo "" ;;
    esac
}

# Function to export volume to a backup file
export_volume() {
    local volume=$1
    local backup_file=$2
    local compress_ext
    compress_ext=$(get_compress_ext)
    local compress_cmd
    compress_cmd=$(get_compress_cmd)

    backup_file="${backup_file}${compress_ext}"

    print_info "Exporting volume: $volume"
    print_info "Backup location: $backup_file"

    # Use a Docker container to tar the volume and write it to the staging dir.
    # The staging dir is inside /var/lib/docker/volumes so Docker can bind-mount it.
    local staging_dir
    staging_dir=$(@coreutils@/bin/dirname "$backup_file")
    local backup_name
    backup_name=$(@coreutils@/bin/basename "$backup_file")

    if [ "$COMPRESS" = "none" ]; then
        @docker@/bin/docker run --rm \
            -v "$volume:/volume:ro" \
            -v "${staging_dir}:/staging" \
            alpine \
            tar cf "/staging/${backup_name}" -C /volume .
    elif [ "$COMPRESS" = "xz" ]; then
        @docker@/bin/docker run --rm \
            -v "$volume:/volume:ro" \
            -v "${staging_dir}:/staging" \
            alpine \
            sh -c "apk add --no-cache xz > /dev/null 2>&1 && tar cf - -C /volume . | ${compress_cmd} > /staging/${backup_name}"
    else
        @docker@/bin/docker run --rm \
            -v "$volume:/volume:ro" \
            -v "${staging_dir}:/staging" \
            alpine \
            sh -c "tar cf - -C /volume . | ${compress_cmd} > /staging/${backup_name}"
    fi

    if [ $? -eq 0 ]; then
        print_success "Volume exported successfully"

        # Calculate and save checksum
        if [ "$VERIFY_CHECKSUM" = true ]; then
            local checksum
            checksum=$(calculate_checksum "$backup_file")
            @coreutils@/bin/echo "$checksum" > "${backup_file}.sha256"
            print_info "Checksum: $checksum"
        fi

        # Show backup file info
        local size
        size=$(@coreutils@/bin/du -h "$backup_file" | @gawk@/bin/awk '{print $1}')
        print_info "Backup size: $size"

        return 0
    else
        print_error "Failed to export volume"
        return 1
    fi
}

# Function to import volume from a backup file
import_volume() {
    local volume=$1
    local backup_file=$2
    local decompress_cmd
    decompress_cmd=$(get_decompress_cmd)

    print_info "Importing volume: $volume"
    print_info "Source backup: $backup_file"

    # Verify checksum if available
    if [ "$VERIFY_CHECKSUM" = true ] && [ -f "${backup_file}.sha256" ]; then
        print_info "Verifying checksum..."
        local expected
        expected=$(@coreutils@/bin/cat "${backup_file}.sha256")
        local actual
        actual=$(calculate_checksum "$backup_file")

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
        @docker@/bin/docker volume create "$volume"
    fi

    # Import: bind-mount the directory containing the backup and the target volume
    local backup_dir
    backup_dir=$(@coreutils@/bin/dirname "$backup_file")
    local backup_name
    backup_name=$(@coreutils@/bin/basename "$backup_file")

    if [ "$COMPRESS" = "none" ] || [[ "$backup_file" != *.gz && "$backup_file" != *.bz2 && "$backup_file" != *.xz ]]; then
        # Uncompressed tar
        @docker@/bin/docker run --rm \
            -v "$volume:/volume" \
            -v "${backup_dir}:/backup:ro" \
            alpine \
            tar xf "/backup/${backup_name}" -C /volume
    elif [[ "$backup_file" == *.xz ]]; then
        @docker@/bin/docker run --rm \
            -v "$volume:/volume" \
            -v "${backup_dir}:/backup:ro" \
            alpine \
            sh -c "apk add --no-cache xz > /dev/null 2>&1 && unxz < /backup/${backup_name} | tar xf - -C /volume"
    else
        @docker@/bin/docker run --rm \
            -v "$volume:/volume" \
            -v "${backup_dir}:/backup:ro" \
            alpine \
            sh -c "${decompress_cmd} < /backup/${backup_name} | tar xf - -C /volume"
    fi

    if [ $? -eq 0 ]; then
        print_success "Volume imported successfully"
        return 0
    else
        print_error "Failed to import volume"
        return 1
    fi
}

# Function to transfer volume directly to a remote host via streamed tar-over-SSH.
# No intermediate files are written to disk on either side.
transfer_volume() {
    local volume=$1
    local dest_volume="${DEST_VOLUME_NAME:-$volume}"
    local compress_cmd
    compress_cmd=$(get_compress_cmd)
    local decompress_cmd
    decompress_cmd=$(get_decompress_cmd)

    print_info "Transferring volume: $volume → ${dest_volume} on ${REMOTE_HOST}"

    # ----- Stop local containers -----
    local local_containers_to_stop=""
    local local_stopped_containers=""

    if [ "$STOP_CONTAINERS" = true ]; then
        if [ -n "$CONTAINER_NAME" ]; then
            local_containers_to_stop="$CONTAINER_NAME"
        else
            local_containers_to_stop=$(get_running_containers_using_volume "$volume")
        fi

        if [ -n "$local_containers_to_stop" ]; then
            print_info "Local containers using volume: $local_containers_to_stop"
            for container in $local_containers_to_stop; do
                if stop_container "$container"; then
                    local_stopped_containers="$local_stopped_containers $container"
                fi
            done
        fi
    else
        print_warning "Transferring without stopping containers - data may be inconsistent"
    fi

    # ----- Stop remote containers -----
    local remote_stopped_containers=""

    if [ "$STOP_CONTAINERS" = true ]; then
        local remote_containers_to_stop=""
        if [ -n "$REMOTE_CONTAINER_NAME" ]; then
            remote_containers_to_stop="$REMOTE_CONTAINER_NAME"
        else
            # Auto-discover running containers using the dest volume on remote
            remote_containers_to_stop=$(remote_ssh "docker ps --filter volume=${dest_volume} --format '{{.Names}}'" 2>/dev/null | @coreutils@/bin/tr '\n' ' ' || true)
        fi

        if [ -n "$remote_containers_to_stop" ]; then
            print_info "Remote containers using destination volume: $remote_containers_to_stop"
            for container in $remote_containers_to_stop; do
                if remote_stop_container "$container"; then
                    remote_stopped_containers="$remote_stopped_containers $container"
                fi
            done
        fi
    fi

    # ----- Ensure destination volume exists on remote -----
    if ! remote_ssh "docker volume inspect ${dest_volume}" &>/dev/null; then
        print_info "Creating destination volume on remote: $dest_volume"
        remote_ssh "docker volume create ${dest_volume}" &>/dev/null || {
            print_error "Failed to create remote volume: $dest_volume"
            restart_local_containers "$local_stopped_containers"
            return 1
        }
    fi

    # ----- Stream tar-over-SSH -----
    # Local: docker run → tar the volume → compress → stdout
    # Pipe over SSH to remote: docker run → decompress stdin → untar into dest volume
    print_info "Streaming volume data to remote host..."

    local xz_install=""
    if [ "$COMPRESS" = "xz" ]; then
        xz_install="apk add --no-cache xz > /dev/null 2>&1 && "
    fi

    local remote_xz_install=""
    if [ "$COMPRESS" = "xz" ]; then
        remote_xz_install="apk add --no-cache xz > /dev/null 2>&1 && "
    fi

    # Remote: receive compressed tar on stdin, decompress, extract into volume
    local remote_cmd="docker run --rm -i -v ${dest_volume}:/volume alpine sh -c '${remote_xz_install}${decompress_cmd} | tar xf - -C /volume'"

    # Local: tar the volume, compress, stream to remote
    if [ "$COMPRESS" = "none" ]; then
        @docker@/bin/docker run --rm \
            -v "$volume:/volume:ro" \
            alpine \
            tar cf - -C /volume . \
        | /run/wrappers/bin/sudo -u "$REMOTE_USER" @openssh@/bin/ssh -p "$SSH_PORT" "${REMOTE_USER}@${REMOTE_HOST}" "$remote_cmd"
    else
        @docker@/bin/docker run --rm \
            -v "$volume:/volume:ro" \
            alpine \
            sh -c "${xz_install}tar cf - -C /volume . | ${compress_cmd}" \
        | /run/wrappers/bin/sudo -u "$REMOTE_USER" @openssh@/bin/ssh -p "$SSH_PORT" "${REMOTE_USER}@${REMOTE_HOST}" "$remote_cmd"
    fi

    local transfer_result=$?

    if [ $transfer_result -eq 0 ]; then
        print_success "Volume data transferred successfully"

        # Verify transfer by comparing file counts
        print_info "Verifying transfer..."
        local local_count
        local_count=$(@docker@/bin/docker run --rm -v "$volume:/volume:ro" alpine sh -c "find /volume -type f | wc -l" 2>/dev/null || echo "?")
        local remote_count
        remote_count=$(remote_ssh "docker run --rm -v ${dest_volume}:/volume:ro alpine sh -c 'find /volume -type f | wc -l'" 2>/dev/null || echo "?")

        if [ "$local_count" = "$remote_count" ] && [ "$local_count" != "?" ]; then
            print_success "Verification passed: $local_count files on both hosts"
        elif [ "$local_count" != "?" ] && [ "$remote_count" != "?" ]; then
            print_warning "File count mismatch: local=$local_count remote=$remote_count"
        else
            print_warning "Could not verify file counts"
        fi
    else
        print_error "Failed to transfer volume data"
    fi

    # ----- Restart remote containers (local containers are NOT restarted — volume has moved) -----
    if [ "$AUTO_RESTART" = true ] && [ -n "$remote_stopped_containers" ]; then
        print_info "Starting containers on remote host..."
        for container in $remote_stopped_containers; do
            remote_start_container "$container"
        done
    fi

    if [ $transfer_result -eq 0 ] && [ -n "$local_stopped_containers" ]; then
        print_warning "Local containers were stopped and NOT restarted (volume has been migrated to ${REMOTE_HOST})"
        print_info "Stopped local containers:$local_stopped_containers"
    fi

    return $transfer_result
}

# Helper: restart local containers on failure
restart_local_containers() {
    local containers=$1
    if [ "$AUTO_RESTART" = true ] && [ -n "$containers" ]; then
        print_info "Restarting local containers after failure..."
        for container in $containers; do
            start_container "$container"
        done
    fi
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

while getopts "v:V:c:C:d:r:f:p:z:nkh" opt; do
    case $opt in
        v) VOLUME_NAME="$OPTARG" ;;
        V) DEST_VOLUME_NAME="$OPTARG" ;;
        c) CONTAINER_NAME="$OPTARG" ;;
        C) REMOTE_CONTAINER_NAME="$OPTARG" ;;
        d) BACKUP_DIR="$OPTARG" ;;
        r) REMOTE_HOST="$OPTARG" ;;
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
check_docker_access
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
                if @docker@/bin/docker ps --format '{{.Names}}' | @gnugrep@/bin/grep -q "^${container}$"; then
                    if stop_container "$container"; then
                        stopped_containers="$stopped_containers $container"
                    fi
                fi
            done
        else
            print_warning "Backing up volume without stopping containers - data may be inconsistent"
        fi

        # Create staging directory inside Docker's data dir
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
                if @docker@/bin/docker ps --format '{{.Names}}' | @gnugrep@/bin/grep -q "^${container}$"; then
                    if stop_container "$container"; then
                        stopped_containers="$stopped_containers $container"
                    fi
                fi
            done
        fi

        # Import volume
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
        # Verify SSH key exists for remote operations
        check_ssh_key

        # Check if volume exists
        if ! check_volume_exists "$VOLUME_NAME"; then
            print_error "Volume does not exist: $VOLUME_NAME"
            exit 1
        fi

        # Show volume info
        mountpoint=$(get_volume_mountpoint "$VOLUME_NAME")
        size=$(get_volume_size "$mountpoint")
        print_info "Volume size: $size"

        # Transfer volume (handles container stop/start internally)
        transfer_volume "$VOLUME_NAME"
        result=$?

        exit $result
        ;;
esac
