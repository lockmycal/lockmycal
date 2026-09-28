#!/bin/bash
# build-docker.sh - Build and run Tymeslot via docker-compose.build.yml
#
# This script:
#   1. Validates that a .env configuration file exists
#   2. Loads and validates all required environment variables from .env
#   3. Builds the Tymeslot image using Dockerfile.docker (via docker compose)
#   4. Optionally starts Tymeslot and its own PostgreSQL container
#
# Dockerfile.docker's default build target has no bundled PostgreSQL server,
# so docker-compose.build.yml runs one as a separate `postgres` container
# alongside `tymeslot`.
#
# Required .env variables:
#   - SECRET_KEY_BASE (64+ chars)
#   - PHX_HOST
#   - POSTGRES_PASSWORD (the sidecar Postgres container has no built-in
#     default the way the old embedded database did)
#
# Run this script from anywhere — it always operates relative to its own
# directory.

set -e  # Exit on any error

# Always run from the repository root (where this script lives)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "========================================"
echo "Building Tymeslot Docker container"
echo "========================================"
echo ""

# ==================== SECTION 1: Environment File Validation ====================
# Check if .env file exists, as it's required for configuration
if [ ! -f .env ]; then
    echo "========================================"
    echo "✗ ERROR: .env file not found!"
    echo "========================================"
    echo ""
    echo "Please copy .env.example to .env and fill in required values:"
    echo ""
    echo "  cp .env.example .env"
    echo "  nano .env  # Edit the file"
    echo ""
    echo "You need to generate a secret for:"
    echo "  - SECRET_KEY_BASE"
    echo ""
    echo "Use: openssl rand -base64 64 | tr -d '\\n'"
    echo "========================================"
    exit 1
fi

echo "✓ Found .env file"

# ==================== SECTION 2: Load Environment Variables ====================
# Source the .env file to make variables available to this script
# set -a exports all variables automatically, set +a turns it off
echo "Loading environment variables from .env..."
set -a  # Export all variables
source .env
set +a  # Stop exporting
echo "✓ Environment variables loaded"

# ==================== SECTION 3: Validate Required Variables ====================
# Collect any missing required environment variables in an array
echo ""
echo "Validating required environment variables..."
MISSING_VARS=()

# Check SECRET_KEY_BASE: must be set and at least 64 characters for Phoenix security
if [ -z "$SECRET_KEY_BASE" ]; then
    MISSING_VARS+=("SECRET_KEY_BASE")
elif [ ${#SECRET_KEY_BASE} -lt 64 ]; then
    echo "========================================"
    echo "✗ ERROR: SECRET_KEY_BASE too short!"
    echo "========================================"
    echo ""
    echo "Current length: ${#SECRET_KEY_BASE} characters"
    echo "Required: At least 64 characters"
    echo ""
    echo "Generate a proper key with:"
    echo "  openssl rand -base64 64 | tr -d '\\n'"
    echo "========================================"
    exit 1
fi

# Check PHX_HOST: required for Phoenix to know its hostname
if [ -z "$PHX_HOST" ]; then
    MISSING_VARS+=("PHX_HOST")
fi

# Check POSTGRES_PASSWORD: required by the sidecar postgres container in
# docker-compose.build.yml, which has no built-in default the way the old
# embedded database did.
if [ -z "$POSTGRES_PASSWORD" ]; then
    MISSING_VARS+=("POSTGRES_PASSWORD")
fi

# If any variables are missing, report them and exit
if [ ${#MISSING_VARS[@]} -ne 0 ]; then
    echo "========================================"
    echo "✗ ERROR: Missing required environment variables!"
    echo "========================================"
    echo ""
    echo "Missing variables:"
    for var in "${MISSING_VARS[@]}"; do
        echo "  - $var"
    done
    echo ""
    echo "Please edit your .env file and set these variables."
    echo ""
    echo "Generate a secure secret with:"
    echo "  openssl rand -base64 64 | tr -d '\\n'"
    echo "========================================"
    exit 1
fi

echo "✓ All required environment variables validated"

# ==================== SECTION 4: Build Docker Image ====================
echo ""
echo "========================================"
echo "Building Docker image..."
echo "========================================"
echo ""

# Build the tymeslot image via docker-compose.build.yml, which also defines
# the sidecar postgres container the database-free default target needs.
docker compose -f docker-compose.build.yml build

echo ""
echo "========================================"
echo "✓ Docker image built successfully!"
echo "========================================"

# ==================== SECTION 5: Interactive Container Startup ====================
# Ask the user if they want to start the containers immediately
echo ""
read -p "Would you like to run Tymeslot now? (y/n): " -n 1 -r
echo ""

if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo ""
    echo "========================================"
    echo "Starting Tymeslot..."
    echo "========================================"
    echo ""

    # Start both the tymeslot and postgres containers. Compose recreates
    # existing containers with the same names, so no manual cleanup is needed.
    docker compose -f docker-compose.build.yml up -d

    # Display startup information and helpful next steps
    echo ""
    echo "========================================"
    echo "✓ Tymeslot started!"
    echo "========================================"
    echo ""
    echo "Access your application at:"
    echo "  http://$PHX_HOST:${PORT:-4000}"
    echo ""
    echo "Note: Please wait for the postgres container's health check and the"
    echo "database migrations to complete before Phoenix starts serving."
    echo ""
    echo "Useful commands:"
    echo "  View logs:    docker compose -f docker-compose.build.yml logs -f tymeslot"
    echo "  Stop:         docker compose -f docker-compose.build.yml stop"
    echo "  Restart:      docker compose -f docker-compose.build.yml restart"
    echo "  Shell access: docker exec -it tymeslot /bin/bash"
    echo "========================================"
else
    # User chose not to run the containers; provide the manual command
    echo ""
    echo "========================================"
    echo "✓ Build complete!"
    echo "========================================"
    echo ""
    echo "To run Tymeslot manually:"
    echo ""
    echo "  docker compose -f docker-compose.build.yml up -d"
    echo ""
    echo "Or using Docker Compose (recommended):"
    echo "  docker compose -f docker-compose.build.yml up -d"
    echo ""
    echo "========================================"
fi