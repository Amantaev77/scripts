#!/bin/bash
set -e

# Параметры
ADMIN_PASSWORD="${COUCHDB_PASSWORD:-admin123}"

apt update && apt install -y curl gnupg

# Импорт GPG-ключа
curl -s https://couchdb.apache.org/repo/keys.asc | gpg --dearmor | tee /usr/share/keyrings/couchdb-archive-keyring.gpg >/dev/null

# Добавление репозитория
source /etc/os-release
echo "deb [signed-by=/usr/share/keyrings/couchdb-archive-keyring.gpg] https://apache.jfrog.io/artifactory/couchdb-deb/ ${VERSION_CODENAME} main" | tee /etc/apt/sources.list.d/couchdb.list

apt update

# Автоматическая установка
echo "couchdb couchdb/setup_mode select standalone" | debconf-set-selections
echo "couchdb couchdb/admin_password password $ADMIN_PASSWORD" | debconf-set-selections
echo "couchdb couchdb/admin_password_again password $ADMIN_PASSWORD" | debconf-set-selections
echo "couchdb couchdb/bind_address string 127.0.0.1" | debconf-set-selections

DEBIAN_FRONTEND=noninteractive apt install -y couchdb
systemctl enable --now couchdb

echo "CouchDB установлен: http://127.0.0.1:5984/_utils/ (admin/$ADMIN_PASSWORD)"
