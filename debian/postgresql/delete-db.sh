#!/bin/bash

# This script automates the removal of a PostgreSQL database and its associated user.
# It is designed to be the counterpart to the add-db.sh script.
# It will:
# 1. Prompt for the database name and the associated username to be removed.
# 2. Perform safety checks to prevent accidental deletion of critical resources.
# 3. Drop the specified PostgreSQL database.
# 4. Drop the specified PostgreSQL user.
# 5. Remove the corresponding remote access rules from pg_hba.conf.
# 6. Restart PostgreSQL to apply the changes.

# Exit immediately if a command exits with a non-zero status.
set -e

# --- 1. Get Database and User Details for Removal ---
echo "--- PostgreSQL Database and User Removal ---"
read -p "Enter the name of the database to remove: " DB_TO_REMOVE
read -p "Enter the username associated with this database to remove: " USER_TO_REMOVE

# Basic validation to ensure inputs are not empty
if [ -z "$DB_TO_REMOVE" ] || [ -z "$USER_TO_REMOVE" ]; then
    echo "Error: Database name and username cannot be empty."
    exit 1
fi

# --- 2. Safety Checks ---
# CRITICAL: Prevent the deletion of the default 'postgres' user.
if [ "$USER_TO_REMOVE" == "postgres" ]; then
    echo "Error: For security reasons, removing the 'postgres' superuser is not allowed."
    exit 1
fi

echo "----------------------------------------"
echo "WARNING: You are about to permanently delete the following:"
echo "  - Database: ${DB_TO_REMOVE}"
echo "  - User:     ${USER_TO_REMOVE}"
echo "This action cannot be undone and all data in the database will be lost."
read -p "Are you sure you want to continue? (type 'yes' to confirm): " CONFIRMATION

if [ "$CONFIRMATION" != "yes" ]; then
    echo "Removal cancelled by user."
    exit 0
fi
echo "----------------------------------------"


# --- 3. Drop PostgreSQL Database and User ---
echo "Proceeding with removal..."

# It's important to terminate any active connections to the database before dropping it.
echo "Terminating active connections to '${DB_TO_REMOVE}'..."
sudo -u postgres psql -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '${DB_TO_REMOVE}';"

echo "Dropping database '${DB_TO_REMOVE}'..."
sudo -u postgres psql -c "DROP DATABASE IF EXISTS ${DB_TO_REMOVE};"

echo "Dropping user '${USER_TO_REMOVE}'..."
sudo -u postgres psql -c "DROP USER IF EXISTS ${USER_TO_REMOVE};"

echo "Database and user have been removed."
echo "----------------------------------------"


# --- 4. Remove Configuration from pg_hba.conf ---
echo "Removing remote access configuration..."

# Find the path to pg_hba.conf dynamically
PG_HBA=$(sudo -u postgres psql -t -P format=unaligned -c 'SHOW hba_file;')

if [ -z "$PG_HBA" ]; then
    echo "Warning: Could not find the path to pg_hba.conf. Skipping rule removal."
else
    echo "Updating pg_hba.conf at: ${PG_HBA}"
    # Use sed to find and delete the line matching the host, database, and user.
    # This command looks for lines starting with 'host', followed by whitespace, the DB name,
    # the user name, and then deletes them. It works for both IPv4 and IPv6 entries.
    sudo sed -i "/^host\s*${DB_TO_REMOVE}\s*${USER_TO_REMOVE}\s*.*/d" "${PG_HBA}"
    echo "Access rules for '${USER_TO_REMOVE}' removed."
fi
echo "----------------------------------------"


# --- 5. Restart PostgreSQL ---
echo "Restarting PostgreSQL service to apply changes..."
sudo systemctl restart postgresql
echo "PostgreSQL service restarted."
echo "----------------------------------------"


# --- 6. Final Summary ---
echo "Removal Complete!"
echo "The database '${DB_TO_REMOVE}' and user '${USER_TO_REMOVE}' have been successfully deleted."
echo "----------------------------------------"