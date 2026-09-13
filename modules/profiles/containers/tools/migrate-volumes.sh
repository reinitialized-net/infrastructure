#!/usr/bin/env bash
#
# Docker Volume Migration Script
# Migrates Docker volumes between hosts using the dedicated docker user.
#
# The docker user has Docker socket access via group membership (no sudo needed)
# and SSH keys are managed through the secrets module + systemd deployment.
#

set -euo pipefail
umask 077

# Use the local daemon and immutable CLI configuration, including when invoked
# as docker, whose home is writable through the migration SFTP service.
export DOCKER_CONFIG=@dockerConfig@
export DOCKER_HOST=unix:///var/run/docker.sock
unset DOCKER_CONTEXT DOCKER_CERT_PATH DOCKER_TLS_VERIFY

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Script version
VERSION="3.1.0"

# Default values
BACKUP_DIR="/mnt/data/docker-volume-backups"
COMPRESS="gzip"
COMPRESS_EXPLICIT=false
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
SSH_KEY="/var/lib/docker-volume-migration/identity"
REMOTE_USER="docker"

# EXIT cleanup only resumes consumers that were running when selected for stopping.
stopped_containers=""
remote_stopped_containers=""
destination_touched=false
migration_succeeded=false
export_temp_dir=""

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
    if [ ! -f "$SSH_KEY" ] && ! /run/wrappers/bin/sudo -u "$REMOTE_USER" @coreutils@/bin/test -f "$SSH_KEY" 2>/dev/null; then
        print_error "SSH key not found at $SSH_KEY"
        print_error "Ensure the volumeMigration secret is configured and the deploy-docker-migration-key service has run."
        exit 1
    fi
}

# Function to run SSH command on remote host (as docker user)
remote_ssh() {
    /run/wrappers/bin/sudo -u "$REMOTE_USER" @openssh@/bin/ssh -F @migrationSshConfig@ -p "$SSH_PORT" "${REMOTE_USER}@${REMOTE_HOST}" "$@"
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
  - Exports default to ${BACKUP_DIR}; imports accept an explicit archive path.
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

# Include running declarative dependents that systemd will stop with a consumer.
get_local_migration_plan() {
    if [ -n "$CONTAINER_NAME" ]; then
        @migrationCommand@/bin/docker-migration-command docker migration-plan "$1" "$CONTAINER_NAME"
    else
        @migrationCommand@/bin/docker-migration-command docker migration-plan "$1"
    fi
}

# Function to stop container
stop_container() {
    local container=$1
    print_info "Stopping container: $container"
    if @migrationCommand@/bin/docker-migration-command docker stop "$container"; then
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
    if @migrationCommand@/bin/docker-migration-command docker start "$container"; then
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

# Export paths must not be replaceable by another local user. Sticky ancestors
# (such as /tmp) are safe only because every existing child is root/caller-owned.
# The output directory itself must be private to trusted owners, not shared.
check_export_directory() {
    local directory=$1
    local ancestor details owner permissions transfer_root
    # SCP/SFTP has the docker UID inside these bind mounts. Even 0700
    # directories there would be writable by that remote principal.
    case "$directory" in
        /home/docker|/home/docker/*|/var/lib/docker/volumes/.migration-staging|/var/lib/docker/volumes/.migration-staging/*|/mnt/data/docker/volumes/.migration-staging|/mnt/data/docker/volumes/.migration-staging/*)
            print_error "Export directory is exposed to migration SCP/SFTP. Choose a private directory outside the transfer roots."
            return 1
            ;;
    esac
    ancestor="$directory"
    while :; do
        if [ -e "$ancestor" ]; then
            # Device/inode comparison also catches aliases through bind mounts.
            for transfer_root in /home/docker /var/lib/docker/volumes/.migration-staging; do
                if [ "$ancestor" -ef "$transfer_root" ]; then
                    print_error "Export directory is exposed to migration SCP/SFTP: $ancestor"
                    return 1
                fi
            done
            if [ ! -d "$ancestor" ]; then
                print_error "Export path is not a directory: $ancestor"
                return 1
            fi
            details=$(@coreutils@/bin/stat -c '%u %a' -- "$ancestor")
            read -r owner permissions <<< "$details"
            if (( owner != 0 && owner != EUID )) ||
                { (( (8#$permissions & 0022) != 0 )) &&
                  { [ "$ancestor" = "$directory" ] || (( (8#$permissions & 01000) == 0 )); }; }; then
                print_error "Unsafe export directory ancestry: $ancestor. Use a root/caller-owned directory without group/other write access."
                return 1
            fi
        fi
        [ "$ancestor" != / ] || break
        ancestor=$(@coreutils@/bin/dirname -- "$ancestor")
    done
}

prepare_export_directory() {
    local directory created_directory
    directory=$(@coreutils@/bin/realpath -m -- "$BACKUP_DIR")
    check_export_directory "$directory"
    @coreutils@/bin/mkdir -p -m 700 -- "$directory"
    # A missing child of a sticky directory can be planted between the first
    # check and mkdir. Reject path redirection and recheck every created ancestor
    # before opening any writable staging paths.
    created_directory=$(@coreutils@/bin/realpath -e -- "$directory")
    if [ "$created_directory" != "$directory" ]; then
        print_error "Export directory changed during creation: $directory"
        return 1
    fi
    check_export_directory "$created_directory"
    BACKUP_DIR="$created_directory"
    # Create before stopping containers; all writable temporary paths stay private.
    export_temp_dir=$(@coreutils@/bin/mktemp -d "$BACKUP_DIR/.migration-backup.XXXXXX")
}

# Function to export volume to a backup file
export_volume() {
    local volume=$1
    local backup_file=$2
    local compress_ext
    compress_ext=$(get_compress_ext)
    local compress_cmd
    compress_cmd=$(get_compress_cmd)

    local final_backup_file="${backup_file}${compress_ext}"
    backup_file="$export_temp_dir/archive"
    # Precreate with restrictive permissions; container truncation retains them.
    : > "$backup_file"

    print_info "Exporting volume: $volume"
    print_info "Backup location: $final_backup_file"

    # Bind only the private export staging directory into the archive container.
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
            sh -eu -o pipefail -c "apk add --no-cache xz > /dev/null 2>&1 && tar cf - -C /volume . | ${compress_cmd} > \"\$1\"" sh "/staging/${backup_name}"
    else
        @docker@/bin/docker run --rm \
            -v "$volume:/volume:ro" \
            -v "${staging_dir}:/staging" \
            alpine \
            sh -eu -o pipefail -c "tar cf - -C /volume . | ${compress_cmd} > \"\$1\"" sh "/staging/${backup_name}"
    fi

    if [ $? -eq 0 ]; then
        print_success "Volume exported successfully"

        # Calculate and save checksum
        if [ "$VERIFY_CHECKSUM" = true ]; then
            local checksum
            checksum=$(calculate_checksum "$backup_file")
            print_info "Checksum: $checksum"
            @coreutils@/bin/echo "$checksum" > "$export_temp_dir/checksum"
        fi

        # Rename replaces symlinks themselves, including links to directories.
        # Publish the checksum first: interruption then fails verification of an
        # old archive rather than leaving a new archive with no checksum.
        if [ "$VERIFY_CHECKSUM" = true ]; then
            @coreutils@/bin/mv -fT -- "$export_temp_dir/checksum" "${final_backup_file}.sha256"
        else
            @coreutils@/bin/rm -f -- "${final_backup_file}.sha256"
        fi
        @coreutils@/bin/mv -fT -- "$backup_file" "$final_backup_file"
        backup_file="$final_backup_file"

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

# Validate a backup before stopping any consumers or changing the destination.
verify_backup() {
    local backup_file=$1
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

    local backup_dir backup_name decompress_cmd xz_install=""
    backup_dir=$(@coreutils@/bin/dirname "$backup_file")
    backup_name=$(@coreutils@/bin/basename "$backup_file")
    # Import compression follows the archive suffix, including .bz2 with no -z.
    if [ "$COMPRESS_EXPLICIT" != true ]; then
        case "$backup_file" in
            *.gz) COMPRESS=gzip ;;
            *.bz2) COMPRESS=bzip2 ;;
            *.xz) COMPRESS=xz ;;
            *) COMPRESS=none ;;
        esac
    fi
    decompress_cmd=$(get_decompress_cmd)
    [ "$COMPRESS" != "xz" ] || xz_install="apk add --no-cache xz > /dev/null 2>&1 && "
    @docker@/bin/docker run --rm -v "${backup_dir}:/backup:ro" alpine \
        sh -eu -o pipefail -c "${xz_install}${decompress_cmd} < \"\$1\" | tar tf - > /dev/null" sh "/backup/${backup_name}"
}

# Function to import volume from a backup file
import_volume() {
    local volume=$1
    local backup_file=$2
    local decompress_cmd
    decompress_cmd=$(get_decompress_cmd)

    print_info "Importing volume: $volume"
    print_info "Source backup: $backup_file"

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

    destination_touched=true

    if [ "$COMPRESS" = "none" ]; then
        # Uncompressed tar
        @docker@/bin/docker run --rm \
            -v "$volume:/volume" \
            -v "${backup_dir}:/backup:ro" \
            alpine \
            tar xf "/backup/${backup_name}" -C /volume
    elif [ "$COMPRESS" = "xz" ]; then
        @docker@/bin/docker run --rm \
            -v "$volume:/volume" \
            -v "${backup_dir}:/backup:ro" \
            alpine \
            sh -eu -o pipefail -c 'apk add --no-cache xz > /dev/null 2>&1 && unxz < "$1" | tar xf - -C /volume' sh "/backup/${backup_name}"
    else
        @docker@/bin/docker run --rm \
            -v "$volume:/volume" \
            -v "${backup_dir}:/backup:ro" \
            alpine \
            sh -eu -o pipefail -c "${decompress_cmd} < \"\$1\" | tar xf - -C /volume" sh "/backup/${backup_name}"
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
    local compress_cmd decompress_cmd
    compress_cmd=$(get_compress_cmd)
    decompress_cmd=$(get_decompress_cmd)

    print_info "Transferring volume: $volume → ${dest_volume} on ${REMOTE_HOST}"

    # Prove SSH/Docker access and discover the destination before any downtime.
    remote_ssh "docker image inspect alpine" > /dev/null 2>&1 || remote_ssh "docker pull alpine"
    if ! remote_ssh "docker volume inspect ${dest_volume}" > /dev/null 2>&1; then
        remote_ssh "docker volume create ${dest_volume}" > /dev/null
    fi
    local remote_running local_running local_plan remote_plan
    if [ "$STOP_CONTAINERS" = true ]; then
        local_plan=$(get_local_migration_plan "$volume")
        remote_plan=$(remote_ssh "docker migration-plan ${dest_volume}${REMOTE_CONTAINER_NAME:+ $REMOTE_CONTAINER_NAME}")
        stopped_containers="$local_plan"
        for container in $stopped_containers; do
            stop_container "$container"
        done
        remote_stopped_containers="$remote_plan"
        for container in $remote_stopped_containers; do
            remote_stop_container "$container"
        done
        # Fail closed if an explicit -c/-C omitted another writer or a service restarted.
        local_running=$(get_running_containers_using_volume "$volume")
        remote_running=$(remote_ssh "docker ps --filter volume=${dest_volume} --format '{{.Names}}'")
        if [ -n "$local_running" ] || [ -n "$remote_running" ]; then
            print_error "A container is still using the source or destination volume"
            return 1
        fi
    else
        print_warning "Transferring without stopping containers - data may be inconsistent"
    fi

    local xz_install=""
    if [ "$COMPRESS" = "xz" ]; then
        xz_install="apk add --no-cache xz > /dev/null 2>&1 && "
    fi
    local remote_cmd="docker run --rm -i -v ${dest_volume}:/volume alpine sh -eu -o pipefail -c '${xz_install}${decompress_cmd} | tar xf - -C /volume'"

    print_info "Streaming volume data to remote host..."
    destination_touched=true
    if [ "$COMPRESS" = "none" ]; then
        @docker@/bin/docker run --rm -v "$volume:/volume:ro" alpine tar cf - -C /volume . \
            | remote_ssh "$remote_cmd"
    else
        @docker@/bin/docker run --rm -v "$volume:/volume:ro" alpine \
            sh -eu -o pipefail -c "${xz_install}tar cf - -C /volume . | ${compress_cmd}" \
            | remote_ssh "$remote_cmd"
    fi

    # A failed verification must not activate the destination.
    print_info "Verifying transfer..."
    local local_count remote_count
    local_count=$(@docker@/bin/docker run --rm -v "$volume:/volume:ro" alpine sh -eu -o pipefail -c 'find /volume -type f | wc -l')
    remote_count=$(remote_ssh "docker run --rm -v ${dest_volume}:/volume:ro alpine sh -eu -o pipefail -c 'find /volume -type f | wc -l'")
    if [ "$local_count" != "$remote_count" ]; then
        print_error "File count mismatch: local=$local_count remote=$remote_count"
        return 1
    fi
    print_success "Volume transferred and verified: $local_count files on both hosts"
}

# Keep cleanup outside the operation functions so errexit and signals cannot skip it.
cleanup() {
    local status=$?
    trap - EXIT
    set +e
    [ -z "$export_temp_dir" ] || @coreutils@/bin/rm -rf -- "$export_temp_dir"
    if [ "$AUTO_RESTART" = true ]; then
        if [ "$MODE" = "import" ] && [ "$destination_touched" = true ] && [ "$migration_succeeded" != true ]; then
            print_warning "Restore failed after writing the destination; its containers remain stopped. Restore a verified backup before starting them."
        elif [ "$MODE" != "transfer" ] || [ "$migration_succeeded" != true ]; then
            for container in $stopped_containers; do
                start_container "$container" || status=1
            done
        elif [ -n "$stopped_containers" ]; then
            print_warning "Local containers remain stopped after migration:$stopped_containers"
        fi
        if [ "$destination_touched" != true ] || [ "$migration_succeeded" = true ]; then
            for container in $remote_stopped_containers; do
                remote_start_container "$container" || status=1
            done
        elif [ -n "$remote_stopped_containers" ]; then
            print_warning "Transfer failed after writing the destination; remote containers remain stopped. The source volume is intact."
        fi
    fi
    exit "$status"
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
        z) COMPRESS="$OPTARG"; COMPRESS_EXPLICIT=true ;;
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

# Reject option/shell syntax in names before constructing remote command strings.
for name in "$VOLUME_NAME" "${DEST_VOLUME_NAME:-$VOLUME_NAME}" "${CONTAINER_NAME:-unused}" "${REMOTE_CONTAINER_NAME:-unused}"; do
    if [[ ! "$name" =~ ^[a-zA-Z0-9][a-zA-Z0-9_.-]*$ ]]; then
        print_error "Invalid Docker volume or container name: $name"
        exit 1
    fi
done
if [[ ! "$COMPRESS" =~ ^(gzip|bzip2|xz|none)$ ]]; then
    print_error "Unsupported compression: $COMPRESS"
    exit 1
fi
if [[ ! "$SSH_PORT" =~ ^[0-9]{1,5}$ ]] || ((10#$SSH_PORT < 1 || 10#$SSH_PORT > 65535)); then
    print_error "SSH port must be between 1 and 65535"
    exit 1
fi

# Main execution. All failure paths and signals pass through the same cleanup.
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
check_docker_access
print_info "=== Docker Volume Migration Tool v${VERSION} ==="
print_info "Mode: $MODE"
print_info "Volume: $VOLUME_NAME"
@docker@/bin/docker image inspect alpine > /dev/null 2>&1 || @docker@/bin/docker pull alpine

case $MODE in
    export|import)
        if [ "$MODE" = "export" ]; then
            operation_volume="$VOLUME_NAME"
            if ! check_volume_exists "$operation_volume"; then
                print_error "Volume does not exist: $operation_volume"
                exit 1
            fi
            # Check staging access before any containers are stopped.
            prepare_export_directory
        else
            operation_volume="${DEST_VOLUME_NAME:-$VOLUME_NAME}"
            if [ ! -f "$BACKUP_FILE" ]; then
                print_error "Backup file does not exist: $BACKUP_FILE"
                exit 1
            fi
            BACKUP_FILE=$(@coreutils@/bin/realpath -e "$BACKUP_FILE")
            verify_backup "$BACKUP_FILE"
        fi

        if [ "$STOP_CONTAINERS" = true ]; then
            stopped_containers=$(get_local_migration_plan "$operation_volume")
            for container in $stopped_containers; do
                stop_container "$container"
            done
            running_containers=$(get_running_containers_using_volume "$operation_volume")
            if [ -n "$running_containers" ]; then
                print_error "A container is still using the volume: $running_containers"
                exit 1
            fi
        else
            print_warning "Copying without stopping containers - data may be inconsistent"
        fi

        if [ "$MODE" = "export" ]; then
            export_volume "$operation_volume" "${BACKUP_DIR}/${VOLUME_NAME}.tar"
        else
            import_volume "$operation_volume" "$BACKUP_FILE"
        fi
        migration_succeeded=true
        ;;
    transfer)
        check_ssh_key
        if ! check_volume_exists "$VOLUME_NAME"; then
            print_error "Volume does not exist: $VOLUME_NAME"
            exit 1
        fi
        transfer_volume "$VOLUME_NAME"
        migration_succeeded=true
        ;;
esac
