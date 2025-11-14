#!/bin/bash
set -euo pipefail

# Nomad Server Pterodactyl Egg Entrypoint
# Handles installation, configuration, and server launch

cd /home/container || exit 1

# --- Helper Functions ---
check_dependencies() {
    echo "[INFO] Checking for required dependencies..."
    local missing=0
    for cmd in curl wget aria2c unzip jq wine64 xvfb-run ip; do
        if ! command -v "$cmd" &> /dev/null; then
            echo "[ERROR] Dependency missing: $cmd. Please install it in your Dockerfile."
            missing=1
        fi
    done
    if [ "$missing" -eq 1 ]; then
        exit 1
    fi
    echo "[SUCCESS] All dependencies are installed."
}

# --- Script Start ---
check_dependencies

# Print startup banner
echo "=========================================="
echo "   Nomad Server - Pterodactyl Edition"
echo "=========================================="
echo ""

# Define installation paths
INSTALL_DIR="/home/container/Nomad"
WINE_PREFIX_DIR="/home/container/.wine"
INSTALLER_PATH="/home/container/nomad.zip"
SERVER_EXE="${INSTALL_DIR}/Nomad.exe"
CONFIG_DIR="${INSTALL_DIR}/Nomad Server/Config"

# Wine environment setup
export WINEPREFIX="${WINE_PREFIX_DIR}"
export WINEARCH="win64"
export WINEDLLOVERRIDES="winemenubuilder.exe=d"
export DISPLAY=:0.0

# Set internal Docker IP for binding
INTERNAL_IP=$(ip -4 addr show eth0 | grep -oP '(?<=inet\s)\d+(\.\d+){3}' || echo "0.0.0.0")
export INTERNAL_IP

echo "Container User: ${USER}"
echo "Working Directory: $(pwd)"
echo "Internal IP: ${INTERNAL_IP}"
echo ""

# Function: Download Nomad installer
download_installer() {
    echo "[INFO] Downloading Nomad installer..."
    
    if [ -z "${NOMAD_DOWNLOAD_URL}" ]; then
        echo "[ERROR] NOMAD_DOWNLOAD_URL environment variable is not set!"
        echo "[ERROR] Please set this variable in your egg configuration."
        exit 1
    fi
    
    echo "[INFO] Download URL: ${NOMAD_DOWNLOAD_URL}"
    
    # Try aria2c first for faster downloads (with progress)
    if command -v aria2c &> /dev/null; then
        echo "[INFO] Using aria2c (multi-connection download)..."
        if aria2c \
            --check-certificate=false \
            --max-connection-per-server=16 \
            --split=16 \
            --min-split-size=1M \
            --file-allocation=none \
            --summary-interval=1 \
            --allow-overwrite=true \
            --out="$(basename ${INSTALLER_PATH})" \
            --dir="$(dirname ${INSTALLER_PATH})" \
            "${NOMAD_DOWNLOAD_URL}"; then
            echo "[SUCCESS] Download completed with aria2c."
            return 0
        else
            echo "[WARNING] aria2c failed, trying wget..."
        fi
    fi
    
    # Fallback to wget
    echo "[INFO] Using wget for download..."
    if wget --no-check-certificate --show-progress -q -O "${INSTALLER_PATH}" "${NOMAD_DOWNLOAD_URL}"; then
        echo "[SUCCESS] Download completed with wget."
        return 0
    else
        echo "[ERROR] Failed to download installer!"
        exit 1
    fi
}

# Function: Extract installer
extract_installer() {
    echo "[INFO] Extracting Nomad installer..."
    
    if [ ! -f "${INSTALLER_PATH}" ]; then
        echo "[ERROR] Installer file not found at ${INSTALLER_PATH}"
        exit 1
    fi
    
    # Get file size for verification
    FILE_SIZE=$(du -h "${INSTALLER_PATH}" | cut -f1)
    echo "[INFO] Installer size: ${FILE_SIZE}"
    
    mkdir -p "${INSTALL_DIR}"
    
    if ! unzip -q -o "${INSTALLER_PATH}" -d "${INSTALL_DIR}"; then
        echo "[ERROR] Failed to extract installer!"
        exit 1
    fi
    
    echo "[SUCCESS] Extraction completed."
}

# Function: Initialize Wine prefix
initialize_wine() {
    echo "[INFO] Initializing Wine environment..."
    
    if [ ! -d "${WINE_PREFIX_DIR}" ]; then
        echo "[INFO] Creating Wine prefix (this may take a moment)..."
        WINEDLLOVERRIDES="mscoree,mshtml=" wineboot -u 2>/dev/null
        wineserver -w
        echo "[SUCCESS] Wine prefix created."
    else
        echo "[INFO] Wine prefix already exists."
    fi
}

# Function: Setup configuration directory
setup_config() {
    echo "[INFO] Setting up configuration directory..."
    mkdir -p "${CONFIG_DIR}"
    
    # Set permissions if possible
    chmod -R 755 "${CONFIG_DIR}" 2>/dev/null || true
    
    echo "[SUCCESS] Configuration directory ready."
}

# Function: Verify installation
verify_installation() {
    echo "[INFO] Verifying installation..."
    
    if [ ! -f "${SERVER_EXE}" ]; then
        echo "[ERROR] Nomad.exe not found at ${SERVER_EXE}"
        echo "[ERROR] Installation verification failed!"
        return 1
    fi
    
    # Get file size for confirmation
    EXE_SIZE=$(du -h "${SERVER_EXE}" | cut -f1)
    echo "[SUCCESS] Found Nomad.exe (${EXE_SIZE})"
    echo "[SUCCESS] Installation verified."
    return 0
}

# Function: Dynamically update config.json from Pterodactyl variables
update_config() {
    echo "[CONFIG] Updating config.json from environment variables..."
    CONFIG_FILE="${CONFIG_DIR}/config.json"

    # Create a default config if it doesn't exist
    if [ ! -f "${CONFIG_FILE}" ]; then
        echo "[CONFIG] config.json not found. Creating a default one."
        cat > "${CONFIG_FILE}" <<-EOF
        {
          "serverPort": 25565,
          "maxPlayers": 30,
          "password": "",
          "serverName": "Nomad Server",
          "maxPing": 1000,
          "motdTimer": 300,
          "kits": false,
          "RegularLoot": 150,
          "MediumLoot": 40,
          "HighLoot": 30,
          "IndustrialLoot": 30,
          "HealthLoot": 30,
          "FoodLoot": 150,
          "FireLoot": 30,
          "SupplyDropTimer": 5400,
          "MiningNodes": 200,
          "BarrelSpawns": 80,
          "PalletSpawns": 50,
          "Zombies": 60,
          "Deers": 40
        }
EOF
    fi

    # Use jq to update values from environment variables if they are set
    echo "[CONFIG] Applying panel settings..."
    TEMP_JSON=$(jq \
        --argjson port "${SERVER_PORT:-$(jq .serverPort ${CONFIG_FILE})}" \
        --argjson players "${MAX_PLAYERS:-$(jq .maxPlayers ${CONFIG_FILE})}" \
        --arg name "${SERVER_NAME:-$(jq .serverName ${CONFIG_FILE})}" \
        --arg password "${SERVER_PASSWORD:-$(jq .password ${CONFIG_FILE})}" \
        --argjson kits_enabled "${KITS_ENABLED:-$(jq .kits ${CONFIG_FILE})}" \
        --argjson regular_loot "${REGULAR_LOOT:-$(jq .RegularLoot ${CONFIG_FILE})}" \
        --argjson medium_loot "${MEDIUM_LOOT:-$(jq .MediumLoot ${CONFIG_FILE})}" \
        --argjson high_loot "${HIGH_LOOT:-$(jq .HighLoot ${CONFIG_FILE})}" \
        --argjson zombies "${ZOMBIES:-$(jq .Zombies ${CONFIG_FILE})}" \
        --argjson deers "${DEERS:-$(jq .Deers ${CONFIG_FILE})}" \
        '.serverPort = $port | .maxPlayers = $players | .serverName = $name | .password = $password | .kits = $kits_enabled | .RegularLoot = $regular_loot | .MediumLoot = $medium_loot | .HighLoot = $high_loot | .Zombies = $zombies | .Deers = $deers' \
        "${CONFIG_FILE}")
    
    echo "${TEMP_JSON}" > "${CONFIG_FILE}"
    echo "[CONFIG] Successfully updated config.json."
    echo "--- Current Settings ---"
    # Use jq to pretty-print the JSON for readability
    echo "${TEMP_JSON}" | jq .
    echo "------------------------"
}

# --- Main Installation Logic ---

echo "[CHECK] Looking for Nomad installation..."

if [ -f "${SERVER_EXE}" ]; then
    echo "[SUCCESS] Nomad server is already installed."
    echo "[INFO] Installation directory: ${INSTALL_DIR}"
else
    echo "[INSTALL] Nomad server not found. Starting installation..."
    echo ""
    
    # Download installer if not present
    if [ ! -f "${INSTALLER_PATH}" ]; then
        download_installer
        echo ""
    else
        echo "[INFO] Installer file already exists, skipping download."
        echo ""
    fi
    
    # Extract installer
    extract_installer
    echo ""
    
    # Initialize Wine
    initialize_wine
    echo ""
    
    # Verify installation
    if verify_installation; then
        echo ""
        echo "[SUCCESS] Installation completed successfully!"
        echo ""
        
        # Clean up installer to save space (optional)
        if [ -f "${INSTALLER_PATH}" ]; then
            FILE_SIZE=$(du -h "${INSTALLER_PATH}" | cut -f1)
            echo "[CLEANUP] Removing installer file (${FILE_SIZE})..."
            rm -f "${INSTALLER_PATH}"
            echo "[SUCCESS] Cleanup completed."
        fi
    else
        echo ""
        echo "[ERROR] Installation failed!"
        echo "[ERROR] Please check the logs above for details."
        exit 1
    fi
fi

echo ""

# Setup configuration
setup_config

# Update config.json from environment variables
update_config

# --- Startup Logic ---

echo ""
echo "=========================================="
echo "   Starting Nomad Server"
echo "=========================================="
echo "[INFO] Server executable: ${SERVER_EXE}"
echo "[INFO] Config directory: ${CONFIG_DIR}"

# Pterodactyl passes the startup command as arguments to this script.
# We need to parse them correctly.
STARTUP_CMD=("$@")

# Log received arguments for debugging
echo "[DEBUG] Received arguments: ${STARTUP_CMD[*]}"
echo "[DEBUG] Argument count: ${#STARTUP_CMD[@]}"

# If no command is provided by Pterodactyl, use a default.
if [ ${#STARTUP_CMD[@]} -eq 0 ] || [ "${STARTUP_CMD[0]}" == "/entrypoint.sh" ] || [ -z "${STARTUP_CMD[0]}" ]; then
    echo "[INFO] No startup command from Pterodactyl. Using default."
    # Set the default command to run
    STARTUP_CMD=(wine64 Nomad/Nomad.exe -batchmode -nographics)
fi

echo "[INFO] Final startup command: ${STARTUP_CMD[*]}"
echo ""

# Run the server in the background
/usr/bin/xvfb-run --auto-servernum --server-args='-screen 0 640x480x24:32' "${STARTUP_CMD[@]}" &

# Capture the Process ID (PID) of the last background command
SERVER_PID=$!

# Wait a few seconds to allow the server to initialize
echo "[INFO] Waiting for server to initialize (5 seconds)..."
sleep 5

# Echo the "done" message for Pterodactyl to detect
echo "[PTERODACTYL_DONE] Server should be running now."

# Wait for the server process to exit
# This keeps the container running as long as the server is running
wait ${SERVER_PID}

echo "[INFO] Server process with PID ${SERVER_PID} has stopped."
exit 0