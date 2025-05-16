#!/bin/sh
# shellcheck shell=dash
set -eu

check_directory() {
    local target="$1"

    if [ ! -d "$target" ]; then
        cat <<EOF
!!!
!!! ERROR
!!! "$target" is not a valid directory, exiting...
!!!
EOF
        exit 127
    fi
}

# Apply envs to uwsgi.ini
update_uwsgi_config() {
    sed -i \
        -e "s|workers = .*|workers = ${UWSGI_WORKERS:-%k}|g" \
        -e "s|threads = .*|threads = ${UWSGI_THREADS:-4}|g" \
        "$UWSGI_SETTINGS_PATH"
}

# Apply envs to settings.yml
update_searxng_config() {
    # Ensure trailing slash in BASE_URL
    # https://www.gnu.org/savannah-checkouts/gnu/bash/manual/bash.html#Shell-Parameter-Expansion
    export BASE_URL="${BASE_URL%/}/"

    sed -i \
        -e "s|base_url: false|base_url: ${BASE_URL:-false}|g" \
        -e "s/instance_name: \"SearXNG\"/instance_name: \"${INSTANCE_NAME:-SearXNG}\"/g" \
        -e "s/autocomplete: \"\"/autocomplete: \"$AUTOCOMPLETE\"/g" \
        -e "s/ultrasecretkey/$(head -c 24 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9')/g" \
        "$SEARXNG_SETTINGS_PATH"
}

# Handle volume mounts
volume_handler() {
    local target="$1"

    # Setup ownership
    if [ "$(stat -c %U "$target")" != "searxng" ] || [ "$(stat -c %G "$target")" != "searxng" ]; then
        if [ "$(id -u)" -eq 0 ]; then
            chown -R searxng:searxng "$target"
        else
            cat <<EOF
!!!
!!! WARNING
!!! "$target" volume is not owned by "searxng"
!!! This may cause issues when running SearXNG
!!!
!!! Run the container as root to automatically fix this issue
!!! Alternatively, you can chown the directory manually:
!!!     chown -R searxng:searxng "$target"
!!!
EOF
        fi
    fi
}

# Handle configuration file updates
config_handler() {
    local target="$1"
    local template="$2"
    local new_template_target="$target.new"

    # Create/Update the configuration file
    if [ -f "$target" ]; then
        if [ "$template" -nt "$target" ]; then
            cat <<EOF
...
... INFORMATION
... Update available for "$target"
... It is recommended to update the configuration file to ensure proper functionality
...
... The new version was placed at "$new_template_target"
... Review the changes and merge them into your existing configuration
...
EOF
            cp -p "$template" "$new_template_target"
        fi
    else
        cat <<EOF
...
... INFORMATION
... File "$target" does not exist, creating...
...
EOF
        cp -p "$template" "$target"
    fi

    # Setup ownership
    if [ "$(stat -c %U "$target")" != "searxng" ] || [ "$(stat -c %G "$target")" != "searxng" ]; then
        if [ "$(id -u)" -eq 0 ]; then
            chown searxng:searxng "$target"
        else
            cat <<EOF
!!!
!!! WARNING
!!! "$target" file is not owned by "searxng"
!!! This may cause issues when running SearXNG
!!!
!!! Run the container as root to automatically fix this issue
!!! Alternatively, you can chown the file manually:
!!!     chown searxng:searxng "$target"
!!!
EOF
        fi
    fi
}

echo "SearXNG $SEARXNG_VERSION"

# Check envs
check_directory "$CONFIG_PATH"
check_directory "$DATA_PATH"

# Check for volume mounts
volume_handler "$CONFIG_PATH"
volume_handler "$DATA_PATH"

# Check for updates in files
config_handler "$UWSGI_SETTINGS_PATH" "/usr/local/searxng/.template/uwsgi.ini"
config_handler "$SEARXNG_SETTINGS_PATH" "/usr/local/searxng/searx/settings.yml"

# Update files
update_uwsgi_config
update_searxng_config

exec /usr/local/searxng/venv/bin/uwsgi --http-socket "$BIND_ADDRESS" "$UWSGI_SETTINGS_PATH"
