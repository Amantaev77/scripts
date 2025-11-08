#!/bin/bash
# auto_install_couchdb.sh

set -e

LOG_FILE="/var/log/couchdb_install.log"
COUCHDB_ADMIN_PASSWORD="SecureAdminPassword123"

echo "Начало установки CouchDB $(date)" | tee -a $LOG_FILE

# Обновление системы
echo "Обновление пакетов..." | tee -a $LOG_FILE
apt update && apt upgrade -y >> $LOG_FILE 2>&1

# Установка зависимостей
echo "Установка зависимостей..." | tee -a $LOG_FILE
apt install -y curl wget gnupg apt-transport-https >> $LOG_FILE 2>&1

# Установка Erlang
echo "Установка Erlang..." | tee -a $LOG_FILE
apt install -y erlang erlang-dev >> $LOG_FILE 2>&1

# Добавление репозитория CouchDB
echo "Добавление репозитория CouchDB..." | tee -a $LOG_FILE
curl -L https://couchdb.apache.org/repo/keys.asc | gpg --dearmor -o /usr/share/keyrings/couchdb-archive-keyring.gpg >> $LOG_FILE 2>&1
source /etc/os-release
echo "deb [signed-by=/usr/share/keyrings/couchdb-archive-keyring.gpg] https://apache.jfrog.io/artifactory/couchdb-deb/ ${VERSION_CODENAME} main" | tee /etc/apt/sources.list.d/couchdb.list >> $LOG_FILE 2>&1

# Установка CouchDB
echo "Установка CouchDB..." | tee -a $LOG_FILE
apt update >> $LOG_FILE 2>&1
apt install -y couchdb >> $LOG_FILE 2>&1

# Запуск службы
echo "Запуск службы CouchDB..." | tee -a $LOG_FILE
systemctl enable couchdb >> $LOG_FILE 2>&1
systemctl start couchdb >> $LOG_FILE 2>&1

# Ожидание запуска
sleep 10

# Создание администратора
echo "Создание администратора..." | tee -a $LOG_FILE
curl -X PUT http://localhost:5984/_node/_local/_config/admins/admin -d "\"$COUCHDB_ADMIN_PASSWORD\"" >> $LOG_FILE 2>&1

echo "Установка завершена!" | tee -a $LOG_FILE
echo "Пароль администратора: $COUCHDB_ADMIN_PASSWORD" | tee -a $LOG_FILE
echo "CouchDB доступен по адресу: http://localhost:5984/_utils/" | tee -a $LOG_FILE
