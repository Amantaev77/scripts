#!/bin/bash
set -e

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}=== Автоматическая установка CouchDB на Debian ===${NC}\n"

# Параметры установки (измените при необходимости)
ADMIN_USER="admin"
ADMIN_PASSWORD="${COUCHDB_PASSWORD:-couchdb_password_123}"
BIND_ADDRESS="127.0.0.1"
BIND_PORT="5984"
SETUP_MODE="standalone"  # или "clustered"

# Функция для проверки ошибок
check_error() {
    if [ $? -ne 0 ]; then
        echo -e "${RED}Ошибка: $1${NC}"
        exit 1
    fi
}

# Обновляем систему и устанавливаем зависимости
echo -e "${YELLOW}[1/5] Обновление системы и установка зависимостей...${NC}"
apt update
check_error "Ошибка при обновлении apt"

apt install -y curl apt-transport-https gnupg lsb-release
check_error "Ошибка при установке зависимостей"

# Импортируем GPG-ключ CouchDB
echo -e "${YELLOW}[2/5] Добавление GPG-ключа CouchDB...${NC}"
curl -s https://couchdb.apache.org/repo/keys.asc | gpg --dearmor | tee /usr/share/keyrings/couchdb-archive-keyring.gpg >/dev/null 2>&1
check_error "Ошибка при импорте GPG-ключа"

# Добавляем репозиторий CouchDB
echo -e "${YELLOW}[3/5] Добавление репозитория CouchDB...${NC}"
source /etc/os-release
echo "deb [signed-by=/usr/share/keyrings/couchdb-archive-keyring.gpg] https://apache.jfrog.io/artifactory/couchdb-deb/ ${VERSION_CODENAME} main" | tee /etc/apt/sources.list.d/couchdb.list >/dev/null
check_error "Ошибка при добавлении репозитория"

# Обновляем список пакетов
echo -e "${YELLOW}[4/5] Обновление списка пакетов...${NC}"
apt update
check_error "Ошибка при обновлении списка пакетов"

# Предварительная настройка через debconf для автоматической установки
echo -e "${YELLOW}[5/5] Автоматическая установка CouchDB...${NC}"
echo "couchdb couchdb/setup_mode select ${SETUP_MODE}" | debconf-set-selections
echo "couchdb couchdb/admin_username string ${ADMIN_USER}" | debconf-set-selections
echo "couchdb couchdb/admin_password password ${ADMIN_PASSWORD}" | debconf-set-selections
echo "couchdb couchdb/admin_password_again password ${ADMIN_PASSWORD}" | debconf-set-selections
echo "couchdb couchdb/bind_address string ${BIND_ADDRESS}" | debconf-set-selections

# Устанавливаем CouchDB без интерактивных запросов
DEBIAN_FRONTEND=noninteractive apt install -y couchdb
check_error "Ошибка при установке CouchDB"

# Включаем автозагрузку
echo -e "${YELLOW}Включение автозагрузки CouchDB...${NC}"
systemctl enable couchdb
check_error "Ошибка при включении автозагрузки"

# Запускаем сервис
echo -e "${YELLOW}Запуск сервиса CouchDB...${NC}"
systemctl start couchdb
check_error "Ошибка при запуске CouchDB"

# Проверяем статус
echo -e "${YELLOW}Проверка статуса CouchDB...${NC}"
systemctl status couchdb

# Тестируем доступность
sleep 2
echo -e "\n${YELLOW}Проверка доступности CouchDB...${NC}"
if curl -s http://${BIND_ADDRESS}:${BIND_PORT}/ | grep -q "couchdb"; then
    echo -e "${GREEN}✓ CouchDB успешно установлен и запущен!${NC}"
    echo -e "\n${GREEN}Информация о сервере:${NC}"
    curl -s http://${BIND_ADDRESS}:${BIND_PORT}/ | python3 -m json.tool
    echo -e "\n${GREEN}Веб-интерфейс доступен по адресу:${NC} http://${BIND_ADDRESS}:${BIND_PORT}/_utils/"
    echo -e "${GREEN}Имя пользователя:${NC} ${ADMIN_USER}"
    echo -e "${GREEN}Пароль:${NC} ${ADMIN_PASSWORD}\n"
else
    echo -e "${RED}✗ Ошибка: CouchDB не отвечает на запросы${NC}"
    exit 1
fi
