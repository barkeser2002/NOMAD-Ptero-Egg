#!/bin/bash
set -e  # Exit on error

cd /home/container

# Nomad Server Docker Container Entrypoint
# Handles installation, configuration, and server launch

echo "=== Nomad Server Installer & Launcher ==="

# Define installation paths
INSTALL_DIR="/home/container/Nomad"
WINE_PREFIX_DIR="/home/container/.wine"
INSTALLER_PATH="/home/container/nomad.zip"
SERVER_EXE="${INSTALL_DIR}/Nomad.exe"
CONFIG_PATH="/home/container/.wine/drive_c/users/container/Saved Games/Nomad/Config"

# Wine environment setup
export WINEPREFIX="${WINE_PREFIX_DIR}"
export WINEARCH="win64"
export WINEDLLOVERRIDES="winemenubuilder.exe=d"
export DISPLAY=:0.0

# Set PUID and PGID for proper file permissions
export PUID=${SERVER_PUID:-1000}
export PGID=${SERVER_PGID:-1000}

echo "Container UID: ${PUID}, GID: ${PGID}"

# Function: Download Nomad installer
download_installer() {
    echo "=== Downloading Nomad installer ==="
    
    if [ -z "${NOMAD_DOWNLOAD_URL}" ]; then
        echo "ERROR: NOMAD_DOWNLOAD_URL environment variable is not set!"
        exit 1
    fi
    
    echo "Download URL: ${NOMAD_DOWNLOAD_URL}"
    
    # Try aria2c first for faster downloads
    # --check-certificate=false: Skip SSL certificate verification (for self-signed certs)
    # -x 16: Use 16 connections per download
    # -s 16: Split download into 16 segments
    # -k 1M: Set min split size to 1MB
    # --file-allocation=none: Don't pre-allocate file space (faster start)
    # --console-log-level=warn: Reduce console output
    # --allow-overwrite=true: Overwrite existing files
    if command -v aria2c &> /dev/null; then
        echo "Using aria2c for faster download..."
        if aria2c --check-certificate=false -x 16 -s 16 -k 1M --file-allocation=none --console-log-level=warn --allow-overwrite=true -o "$(basename ${INSTALLER_PATH})" -d "$(dirname ${INSTALLER_PATH})" "${NOMAD_DOWNLOAD_URL}"; then
            echo "Download completed successfully with aria2c."
            return 0
        else
            echo "WARNING: aria2c download failed, falling back to wget..."
        fi
    fi
    
    # Fallback to wget if aria2c is not available or failed
    echo "Using wget for download..."
    if ! wget --no-check-certificate -O "${INSTALLER_PATH}" "${NOMAD_DOWNLOAD_URL}"; then
        echo "ERROR: Failed to download installer with wget!"
        exit 1
    fi
    
    echo "Download completed successfully with wget."
}

# Function: Extract installer
extract_installer() {
    echo "=== Extracting Nomad installer ==="
    
    if [ ! -f "${INSTALLER_PATH}" ]; then
        echo "ERROR: Installer file not found at ${INSTALLER_PATH}"
        exit 1
    fi
    
    mkdir -p "${INSTALL_DIR}"
    
    if ! unzip -o "${INSTALLER_PATH}" -d "${INSTALL_DIR}"; then
        echo "ERROR: Failed to extract installer!"
        exit 1
    fi
    
    echo "Extraction completed successfully."
}

# Function: Initialize Wine prefix
initialize_wine() {
    echo "=== Initializing Wine environment ==="
    
    if [ ! -d "${WINE_PREFIX_DIR}" ]; then
        echo "Creating Wine prefix..."
        wineboot -u
        echo "Wine prefix created successfully."
    else
        echo "Wine prefix already exists. Skipping initialization."
    fi
}

# Function: Setup configuration directory
setup_config() {
    echo "=== Setting up configuration directory ==="
    mkdir -p "${CONFIG_PATH}"
    echo "Configuration directory ready at: ${CONFIG_PATH}"
}

# Function: Verify installation
verify_installation() {
    echo "=== Verifying installation ==="
    
    if [ ! -f "${SERVER_EXE}" ]; then
        echo "ERROR: Nomad.exe not found at ${SERVER_EXE}"
        return 1
    fi
    
    echo "Installation verified successfully."
    return 0
}

# --- Main Installation Logic ---

# Check if server is already installed
if [ -f "${SERVER_EXE}" ]; then
    echo "✓ Nomad server already installed."
    echo "Installation directory: ${INSTALL_DIR}"
else
    echo "✗ Nomad server not found. Starting installation..."
    
    # Download installer if not present
    if [ ! -f "${INSTALLER_PATH}" ]; then
        download_installer
    else
        echo "✓ Installer file already exists."
    fi
    
    # Extract installer
    extract_installer
    
    # Initialize Wine
    initialize_wine
    
    # Verify installation
    if verify_installation; then
        echo "✓ Installation completed successfully!"
        # Clean up installer to save space
        echo "Cleaning up installer file..."
        rm -f "${INSTALLER_PATH}"
    else
        echo "✗ Installation failed!"
        exit 1
    fi
fi

# Setup configuration
setup_config

# Launch server
echo ""
echo "=== Starting Nomad Server ==="
echo "Executing startup command: $@"
echo "=============================="
echo ""

# Execute the Pterodactyl startup command
exec "$@"