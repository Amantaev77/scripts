#!/bin/bash
# auto_install_couchdb.sh
# Автоматическая установка CouchDB на Debian/Ubuntu

set -e

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Логирование
LOG_FILE="/var/log/couchdb_install.log"
COUCHDB_ADMIN_PASSWORD="${1:-SecureAdminPassword123!}"
COUCHDB_VERSION="${2:-latest}"

# Функция логирования
log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
    exit 1
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_FILE"
}

# Проверка прав root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "Этот скрипт должен быть запущен с правами root"
    fi
}

# Определение дистрибутива
get_os_info() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$NAME
        VER=$VERSION_ID
        CODENAME=$VERSION_CODENAME
    else
        error "Не удалось определить дистрибутив"
    fi
}

# Обновление системы
update_system() {
    log "Обновление системы..."
    apt update >> "$LOG_FILE" 2>&1 || warning "Не удалось обновить список пакетов"
    apt upgrade -y >> "$LOG_FILE" 2>&1 || warning "Не удалось обновить пакеты"
}

# Установка зависимостей
install_dependencies() {
    log "Установка зависимостей..."
    apt install -y \
        curl \
        wget \
        gnupg \
        software-properties-common \
        apt-transport-https \
        ca-certificates \
        lsb-release \
        erlang \
        erlang-dev \
        erlang-nox \
        erlang-base-hipe >> "$LOG_FILE" 2>&1
}

# Установка последней версии Erlang (опционально)
install_erlang_latest() {
    log "Установка последней версии Erlang..."
    wget -O- https://packages.erlang-solutions.com/ubuntu/erlang_solutions.asc | apt-key add - >> "$LOG_FILE" 2>&1
    echo "deb https://packages.erlang-solutions.com/ubuntu $(lsb_release -cs) contrib" | tee /etc/apt/sources.list.d/erlang-solutions.list >> "$LOG_FILE" 2>&1
    
    apt update >> "$LOG_FILE" 2>&1
    apt install -y erlang erlang-dev >> "$LOG_FILE" 2>&1
}

# Добавление репозитория CouchDB
add_couchdb_repo() {
    log "Добавление репозитория CouchDB..."
    
    # Скачивание и добавление ключа
    curl -L https://couchdb.apache.org/repo/keys.asc | gpg --dearmor -o /usr/share/keyrings/couchdb-archive-keyring.gpg >> "$LOG_FILE" 2>&1
    
    # Определение кодового имени дистрибутива
    source /etc/os-release
    
    # Добавление репозитория
    echo "deb [signed-by=/usr/share/keyrings/couchdb-archive-keyring.gpg] https://apache.jfrog.io/artifactory/couchdb-deb/ ${VERSION_CODENAME} main" | tee /etc/apt/sources.list.d/couchdb.list >> "$LOG_FILE" 2>&1
    
    apt update >> "$LOG_FILE" 2>&1
}

# Установка CouchDB
install_couchdb() {
    log "Установка CouchDB..."
    
    if [ "$COUCHDB_VERSION" = "latest" ]; then
        apt install -y couchdb >> "$LOG_FILE" 2>&1
    else
        apt install -y couchdb=$COUCHDB_VERSION >> "$LOG_FILE" 2>&1
    fi
}

# Настройка CouchDB
configure_couchdb() {
    log "Настройка CouchDB..."
    
    # Создание резервной копии конфигурации
    cp /etc/couchdb/local.ini /etc/couchdb/local.ini.backup
    
    # Базовая конфигурация
    cat > /tmp/couchdb_config.txt << EOF
[chttpd]
bind_address = 0.0.0.0
port = 5984

[httpd]
bind_address = 0.0.0.0
port = 5984
enable_cors = true

[cors]
origins = *
credentials = true
methods = GET, PUT, POST, HEAD, DELETE
headers = accept, authorization, content-type, origin, referer

[log]
level = info
file = /var/log/couchdb/couchdb.log

EOF

    # Применение конфигурации
    cat /tmp/couchdb_config.txt >> /etc/couchdb/local.ini
    rm /tmp/couchdb_config.txt
}

# Запуск и настройка службы
setup_service() {
    log "Настройка службы CouchDB..."
    
    systemctl daemon-reload >> "$LOG_FILE" 2>&1
    systemctl enable couchdb >> "$LOG_FILE" 2>&1
    systemctl start couchdb >> "$LOG_FILE" 2>&1
    
    # Ожидание запуска
    log "Ожидание запуска CouchDB..."
    sleep 10
    
    # Проверка статуса
    if ! systemctl is-active --quiet couchdb; then
        error "CouchDB не запустился"
    fi
}

# Создание администратора
create_admin() {
    log "Создание администратора..."
    
    # Ожидаем пока CouchDB полностью запустится
    local max_attempts=30
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        if curl -s http://localhost:5984/ > /dev/null 2>&1; then
            break
        fi
        log "Попытка $attempt/$max_attempts: Ожидание запуска CouchDB..."
        sleep 2
        ((attempt++))
    done
    
    if [ $attempt -gt $max_attempts ]; then
        error "CouchDB не запустился за отведенное время"
    fi
    
    # Создание администратора
    if curl -X PUT http://localhost:5984/_node/_local/_config/admins/admin -d "\"$COUCHDB_ADMIN_PASSWORD\"" >> "$LOG_FILE" 2>&1; then
        log "Администратор создан успешно"
    else
        warning "Не удалось создать администратора через API, пробуем через конфигурационный файл"
        echo "admin = $COUCHDB_ADMIN_PASSWORD" >> /etc/couchdb/local.ini
        systemctl restart couchdb >> "$LOG_FILE" 2>&1
        sleep 5
    fi
}

# Настройка брандмауэра
setup_firewall() {
    log "Настройка брандмауэра..."
    
    if command -v ufw > /dev/null 2>&1 && ufw status | grep -q "active"; then
        ufw allow 5984/tcp >> "$LOG_FILE" 2>&1
        log "Порт 5984 открыт в UFW"
    fi
    
    if command -v firewall-cmd > /dev/null 2>&1; then
        firewall-cmd --permanent --add-port=5984/tcp >> "$LOG_FILE" 2>&1
        firewall-cmd --reload >> "$LOG_FILE" 2>&1
        log "Порт 5984 открыт в firewalld"
    fi
}

# Проверка установки
verify_installation() {
    log "Проверка установки..."
    
    # Проверка службы
    if systemctl is-active --quiet couchdb; then
        log "✓ Служба CouchDB запущена"
    else
        error "✗ Служба CouchDB не запущена"
    fi
    
    # Проверка порта
    if netstat -tln | grep -q ":5984"; then
        log "✓ CouchDB слушает на порту 5984"
    else
        error "✗ CouchDB не слушает на порту 5984"
    fi
    
    # Проверка HTTP доступа
    if curl -s http://localhost:5984/ | grep -q "couchdb"; then
        log "✓ HTTP доступ работает"
    else
        error "✗ HTTP доступ не работает"
    fi
    
    # Проверка аутентификации
    if curl -s -u admin:"$COUCHDB_ADMIN_PASSWORD" http://localhost:5984/_session | grep -q "ok"; then
        log "✓ Аутентификация работает"
    else
        warning "✗ Проблемы с аутентификацией"
    fi
}

# Настройка CORS
setup_cors() {
    log "Настройка CORS..."
    
    curl -X PUT -u admin:"$COUCHDB_ADMIN_PASSWORD" http://localhost:5984/_node/_local/_config/httpd/enable_cors -d '"true"' >> "$LOG_FILE" 2>&1 || true
    curl -X PUT -u admin:"$COUCHDB_ADMIN_PASSWORD" http://localhost:5984/_node/_local/_config/cors/origins -d '"*"' >> "$LOG_FILE" 2>&1 || true
    curl -X PUT -u admin:"$COUCHDB_ADMIN_PASSWORD" http://localhost:5984/_node/_local/_config/cors/credentials -d '"true"' >> "$LOG_FILE" 2>&1 || true
}

# Финальный вывод
show_summary() {
    echo
    echo "=================================================="
    echo "Установка CouchDB завершена успешно!"
    echo "=================================================="
    echo "Доступ к веб-интерфейсу: http://$(hostname -I | awk '{print $1}'):5984/_utils/"
    echo "Логин: admin"
    echo "Пароль: $COUCHDB_ADMIN_PASSWORD"
    echo "Лог установки: $LOG_FILE"
    echo
    echo "Проверка работы:"
    echo "curl -u admin:'$COUCHDB_ADMIN_PASSWORD' http://localhost:5984/_session"
    echo "=================================================="
}

# Главная функция
main() {
    log "Начало установки CouchDB"
    log "Пароль администратора: $COUCHDB_ADMIN_PASSWORD"
    log "Версия CouchDB: $COUCHDB_VERSION"
    
    check_root
    get_os_info
    log "Установка на: $OS $VER"
    
    update_system
    install_dependencies
    add_couchdb_repo
    install_couchdb
    configure_couchdb
    setup_service
    create_admin
    setup_firewall
    setup_cors
    verify_installation
    show_summary
    
    log "Установка завершена успешно!"
}

# Обработка аргументов командной строки
while [[ $# -gt 0 ]]; do
    case $1 in
        -p|--password)
            COUCHDB_ADMIN_PASSWORD="$2"
            shift 2
            ;;
        -v|--version)
            COUCHDB_VERSION="$2"
            shift 2
            ;;
        -h|--help)
            echo "Использование: $0 [OPTIONS]"
            echo "Options:"
            echo "  -p, --password PASSWORD   Пароль администратора (по умолчанию: SecureAdminPassword123!)"
            echo "  -v, --version VERSION     Версия CouchDB (по умолчанию: latest)"
            echo "  -h, --help                Показать эту справку"
            exit 0
            ;;
        *)
            error "Неизвестный параметр: $1"
            ;;
    esac
done

# Запуск главной функции
main
