#!/bin/bash

# This script adds a new database and a new user to an existing PostgreSQL server.
# It is designed to be run after the initial server setup is complete.
# It will:
# 1. Prompt for the new database name, username, and password.
# 2. Create the specified PostgreSQL user and database.
# 3. Grant the new user full privileges on the new database.
# 4. Update pg_hba.conf to allow remote connections for the new user.
# 5. Restart PostgreSQL to apply the changes.

# Exit immediately if a command exits with a non-zero status.
set -e

# --- 1. Get New Database and User Details ---
echo "--- New PostgreSQL Database and User Setup ---"
read -p "Enter the name for the new database: " NEW_DB_NAME
read -p "Enter the username for the new user: " NEW_DB_USER
read -sp "Enter a secure password for the new user: " NEW_DB_PASSWORD
echo # Add a newline after the password prompt

# Basic validation to ensure inputs are not empty
if [ -z "$NEW_DB_NAME" ] || [ -z "$NEW_DB_USER" ] || [ -z "$NEW_DB_PASSWORD" ]; then
    echo "Error: Database name, username, and password cannot be empty."
    exit 1
fi

echo "----------------------------------------"

# --- 2. Create PostgreSQL Database and User ---
echo "Creating PostgreSQL database '${NEW_DB_NAME}' and user '${NEW_DB_USER}'..."
# Using sudo -u postgres to execute commands as the 'postgres' user.
sudo -u postgres psql -c "CREATE DATABASE ${NEW_DB_NAME};"
sudo -u postgres psql -c "CREATE USER ${NEW_DB_USER} WITH PASSWORD '${NEW_DB_PASSWORD}';"
sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE ${NEW_DB_NAME} TO ${NEW_DB_USER};"
echo "Database and user created successfully."
echo "----------------------------------------"

# --- 3. Configure PostgreSQL for Remote Connections ---
# We only need to edit pg_hba.conf to add a rule for the new user.
# The listen_addresses setting in postgresql.conf is a one-time server setup.

echo "Configuring PostgreSQL for remote connections for the new user..."

# Find the path to pg_hba.conf dynamically
PG_HBA=$(sudo -u postgres psql -t -P format=unaligned -c 'SHOW hba_file;')

if [ -z "$PG_HBA" ]; then
    echo "Error: Could not find the path to pg_hba.conf."
    exit 1
fi

echo "Updating pg_hba.conf at: ${PG_HBA}"

# Add a new line to pg_hba.conf to allow the new user to connect from any IP
# using md5 password authentication.
# The format is: TYPE DATABASE USER ADDRESS METHOD
echo "host    ${NEW_DB_NAME}    ${NEW_DB_USER}    0.0.0.0/0    md5" | sudo tee -a "${PG_HBA}"
echo "host    ${NEW_DB_NAME}    ${NEW_DB_USER}    ::/0         md5" | sudo tee -a "${PG_HBA}" # For IPv6

echo "PostgreSQL access rule added."
echo "----------------------------------------"

# --- 4. Restart PostgreSQL ---
echo "Restarting PostgreSQL service to apply changes..."
sudo systemctl restart postgresql
echo "PostgreSQL service restarted."
echo "----------------------------------------"

# --- 5. Final Summary ---
echo "Setup Complete!"
echo "You can now connect to the new database using:"
echo "Database: ${NEW_DB_NAME}"
echo "User: ${NEW_DB_USER}"
echo "Password: [the password you entered]"
echo "Host: Your server's IP address"
echo "Port: 5432"
echo "----------------------------------------"