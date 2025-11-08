#!/bin/bash
# quick_install_couchdb.sh

set -e

PASSWORD="${1:-CouchDB123!}"
LOG_FILE="/var/log/couchdb_quick_install.log"

echo "Быстрая установка CouchDB..." | tee -a "$LOG_FILE"

# Обновление и установка зависимостей
apt update && apt upgrade -y >> "$LOG_FILE" 2>&1
apt install -y curl wget gnupg >> "$LOG_FILE" 2>&1

# Установка Erlang
apt install -y erlang erlang-dev >> "$LOG_FILE" 2>&1

# Добавление репозитория CouchDB
curl -L https://couchdb.apache.org/repo/keys.asc | gpg --dearmor -o /usr/share/keyrings/couchdb.gpg
echo "deb [signed-by=/usr/share/keyrings/couchdb.gpg] https://apache.jfrog.io/artifactory/couchdb-deb/ $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/couchdb.list

# Установка CouchDB
apt update >> "$LOG_FILE" 2>&1
apt install -y couchdb >> "$LOG_FILE" 2>&1

# Запуск службы
systemctl enable couchdb >> "$LOG_FILE" 2>&1
systemctl start couchdb >> "$LOG_FILE" 2>&1

# Ожидание запуска
sleep 10

# Создание администратора
curl -X PUT http://localhost:5984/_node/_local/_config/admins/admin -d "\"$PASSWORD\"" >> "$LOG_FILE" 2>&1

echo "Установка завершена!" | tee -a "$LOG_FILE"
echo "URL: http://$(hostname -I | awk '{print $1}'):5984/_utils/" | tee -a "$LOG_FILE"
echo "User: admin" | tee -a "$LOG_FILE"
echo "Password: $PASSWORD" | tee -a "$LOG_FILE"
