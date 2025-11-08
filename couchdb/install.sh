#!/bin/bash
set -e

# Устанавливаем необходимые утилиты
sudo apt update
sudo apt install -y curl apt-transport-https gnupg lsb-release

# Импортируем GPG-ключ CouchDB
curl https://couchdb.apache.org/repo/keys.asc | gpg --dearmor | sudo tee /usr/share/keyrings/couchdb-archive-keyring.gpg >/dev/null

# Добавляем репозиторий CouchDB
echo "deb [signed-by=/usr/share/keyrings/couchdb-archive-keyring.gpg] https://apache.jfrog.io/artifactory/couchdb-deb/ $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/couchdb.list >/dev/null

# Обновляем список пакетов
sudo apt update

# Устанавливаем CouchDB (будет интерактивная настройка standalone/cluster, ip bind и пароль)
sudo apt install -y couchdb

echo "CouchDB установлен, проверьте статус командой: sudo systemctl status couchdb"
echo "Проверьте доступность: curl http://127.0.0.1:5984/"
