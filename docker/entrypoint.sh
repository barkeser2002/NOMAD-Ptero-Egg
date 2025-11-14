#!/bin/bash
cd /home/container

# This script is the entrypoint for the DCS server Docker container.
# It handles installation, updates, configuration generation, and launching the server.

# Ensure script uses Unix-style line endings to prevent 'command not found' errors.[9]
# Pterodactyl's installer can handle this, but it's good practice for local testing.
# dos2unix /home/container/entrypoint.sh

# Define key variables for the DCS installation and configuration.
# The Pterodactyl panel will pass these values as environment variables.
INSTALL_DIR="/home/container/Nomad"
WINE_PREFIX_DIR="/home/container/.wine"
INSTALLER_PATH="/home/container/nomad.zip"
UPDATER_EXE="${INSTALL_DIR}/Nomad.exe"
SERVER_EXE="${INSTALL_DIR}/Nomad.exe"

# Set Wine environment variables.
export WINEPREFIX="${WINE_PREFIX_DIR}"
export WINEARCH="win64"
export WINEDLLOVERRIDES="winemenubuilder.exe=d"
# Use a virtual display for the GUI installer.
export DISPLAY=:0.0

# Function to perform the initial DCS server installation.
install_dcs_server() {
    echo "DCS server not found. Starting installation process..."
    
    # Create a Wine prefix.
    wineboot -u
    
    # After initial install, run the updater to get all files.
    
    echo "DCS server installation completed."
}

# Function to update the DCS server and install modules.


# Function to dynamically generate configuration files from Pterodactyl variables.
generate_config_files() {
    echo "Generating server configuration files..."
    
    # Define a path for the user's saved games, which is where config files are stored.
    # The -w flag in the startup command points the server to this directory.[10]
    SAVED_GAMES_PATH="/home/container/.wine/drive_c/users/container/Saved Games/Nomad/Nomad Server/Config"
    mkdir -p "${SAVED_GAMES_PATH}"

# --- Main Logic ---

# Set PUID and PGID for the container process.
# This ensures file ownership is correct on the host machine.[12]
echo "Setting container PUID and PGID..."
export PUID=${SERVER_PUID}
export PGID=${SERVER_PGID}

# Check if the DCS server is already installed.
if [ -d "${INSTALL_DIR}" ] && [ -n "$(ls -A ${INSTALL_DIR})" ]; then
    install_dcs_server
else
    echo "DCS server already installed. Skipping installation."
    # The server is already installed, so we run the update process.
    xvfb-run -a wine "${SERVER_EXE}" -port 25565 -batchmode -nographics
fi

# Generate configuration files before launching the server.
generate_config_files

# Finally, launch the server using the Pterodactyl startup command.
echo "Environment prepared. Executing Pterodactyl's startup command..."
# The `exec` command replaces the current shell process with the server process.
exec "$@"