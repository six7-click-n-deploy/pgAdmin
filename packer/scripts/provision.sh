#!/usr/bin/env bash
set -euo pipefail

echo "[1/6] Waiting for cloud-init to complete..."
cloud-init status --wait || true

echo "[2/6] Updating package lists and installing prerequisites..."
sudo apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
  curl \
  wget \
  ca-certificates \
  gnupg \
  lsb-release

echo "[3/6] Adding official pgAdmin4 apt repository..."
sudo rm -f /usr/share/keyrings/packages-pgadmin-org.gpg
curl -fsSL https://www.pgadmin.org/static/packages_pgadmin_org.pub \
  | sudo gpg --batch --yes --dearmor -o /usr/share/keyrings/packages-pgadmin-org.gpg

echo "deb [signed-by=/usr/share/keyrings/packages-pgadmin-org.gpg] \
https://ftp.postgresql.org/pub/pgadmin/pgadmin4/apt/$(lsb_release -cs) pgadmin4 main" \
  | sudo tee /etc/apt/sources.list.d/pgadmin4.list > /dev/null

sudo apt-get update

echo "[4/6] Installing pgAdmin4 (web mode) and PostgreSQL..."
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y pgadmin4-web postgresql postgresql-contrib

echo "[5/6] Initializing pgAdmin4 via setup-web.sh (DB will be wiped after)..."
export PGADMIN_SETUP_EMAIL='init@example.com'
export PGADMIN_SETUP_PASSWORD='Init1234!'
sudo --preserve-env=PGADMIN_SETUP_EMAIL,PGADMIN_SETUP_PASSWORD \
  /usr/pgadmin4/bin/setup-web.sh --yes

sudo rm -f /var/lib/pgadmin/pgadmin4.db
sudo rm -f /var/lib/pgadmin/pgadmin4.db-wal
sudo rm -f /var/lib/pgadmin/pgadmin4.db-shm
sudo systemctl stop apache2

echo "[6/6] Loading pagila sample database..."
sudo systemctl start postgresql
sudo -u postgres psql -c "CREATE DATABASE pagila;"
sudo -u postgres psql -c "CREATE USER pagila_user WITH PASSWORD 'pagila';"
sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE pagila TO pagila_user;"

curl -fsSL https://raw.githubusercontent.com/devrimgunduz/pagila/master/pagila-schema.sql \
  -o /tmp/pagila-schema.sql
curl -fsSL https://raw.githubusercontent.com/devrimgunduz/pagila/master/pagila-data.sql \
  -o /tmp/pagila-data.sql
sudo -u postgres psql -d pagila -f /tmp/pagila-schema.sql
sudo -u postgres psql -d pagila -f /tmp/pagila-data.sql
sudo -u postgres psql -d pagila -c "GRANT USAGE ON SCHEMA public TO pagila_user;"
sudo -u postgres psql -d pagila -c "GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO pagila_user;"
sudo -u postgres psql -d pagila -c "GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO pagila_user;"
rm -f /tmp/pagila-schema.sql /tmp/pagila-data.sql
sudo systemctl stop postgresql

echo "Cleanup..."
sudo apt-get clean
sudo rm -rf /var/lib/apt/lists/*

# Reset machine-id (required for cloud-init on cloned images)
sudo truncate -s 0 /etc/machine-id
sudo rm -f /var/lib/dbus/machine-id

echo "Provisioning finished. Image is ready for deployment."
