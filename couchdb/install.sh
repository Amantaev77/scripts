#!/bin/bash
# install.sh
# Установка CouchDB с настройкой кластера

set -e

# Конфигурация
NODE_NAME="${1:-couchdb@localhost}"
CLUSTER_SIZE="${2:-1}"
ADMIN_USER="admin"
ADMIN_PASSWORD="${3:-ClusterAdmin123!}"
LOG_FILE="/var/log/couchdb_cluster_install.log"

# Цвета
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[$(date '+%H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"; }
error() { echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"; exit 1; }

install_couchdb_single() {
    log "Установка CouchDB в режиме single node..."
    
    apt update && apt install -y curl wget gnupg
    apt install -y erlang erlang-dev
    
    curl -L https://couchdb.apache.org/repo/keys.asc | gpg --dearmor -o /usr/share/keyrings/couchdb.gpg
    echo "deb [signed-by=/usr/share/keyrings/couchdb.gpg] https://apache.jfrog.io/artifactory/couchdb-deb/ $(lsb_release -cs) main" > /etc/apt/sources.list.d/couchdb.list
    
    apt update
    apt install -y couchdb
    
    # Настройка
    systemctl enable couchdb
    systemctl start couchdb
    sleep 10
    
    # Создание администратора
    curl -X PUT http://localhost:5984/_node/_local/_config/admins/$ADMIN_USER -d "\"$ADMIN_PASSWORD\""
}

setup_cluster() {
    log "Настройка кластера CouchDB..."
    
    # Включение кластера
    curl -X POST "http://localhost:5984/_cluster_setup" \
        -H "Content-Type: application/json" \
        -u "$ADMIN_USER:$ADMIN_PASSWORD" \
        -d '{"action": "enable_cluster", "bind_address":"0.0.0.0", "username": "'$ADMIN_USER'", "password":"'$ADMIN_PASSWORD'"}' \
        >> "$LOG_FILE" 2>&1
    
    # Завершение настройки кластера
    curl -X POST "http://localhost:5984/_cluster_setup" \
        -H "Content-Type: application/json" \
        -u "$ADMIN_USER:$ADMIN_PASSWORD" \
        -d '{"action": "finish_cluster"}' \
        >> "$LOG_FILE" 2>&1
    
    log "Кластер CouchDB настроен"
}

configure_erlang_cookie() {
    log "Настройка Erlang cookie для кластера..."
    
    local cookie_value="MyClusterCookie123"
    
    # Остановка CouchDB
    systemctl stop couchdb
    
    # Генерация cookie
    echo "$cookie_value" > /var/lib/couchdb/.erlang.cookie
    chown couchdb:couchdb /var/lib/couchdb/.erlang.cookie
    chmod 600 /var/lib/couchdb/.erlang.cookie
    
    # Запись в конфигурацию
    sed -i "s/;certfile =/;-setcookie $cookie_value\n;certfile =/" /etc/couchdb/vm.args
    
    # Запуск CouchDB
    systemctl start couchdb
    sleep 5
}

add_node_to_cluster() {
    local node_ip="$1"
    log "Добавление узла $node_ip в кластер..."
    
    curl -X POST "http://localhost:5984/_cluster_setup" \
        -H "Content-Type: application/json" \
        -u "$ADMIN_USER:$ADMIN_PASSWORD" \
        -d '{"action": "enable_cluster", "bind_address":"0.0.0.0", "username": "'$ADMIN_USER'", "password":"'$ADMIN_PASSWORD'", "port": 5984, "node_count": '$CLUSTER_SIZE', "remote_node": "'$node_ip'", "remote_current_user": "'$ADMIN_USER'", "remote_current_password": "'$ADMIN_PASSWORD'"}' \
        >> "$LOG_FILE" 2>&1
    
    curl -X POST "http://localhost:5984/_cluster_setup" \
        -H "Content-Type: application/json" \
        -u "$ADMIN_USER:$ADMIN_PASSWORD" \
        -d '{"action": "add_node", "host":"'$node_ip'", "port": 5984, "username": "'$ADMIN_USER'", "password":"'$ADMIN_PASSWORD'"}' \
        >> "$LOG_FILE" 2>&1
}

show_cluster_info() {
    log "Информация о кластере:"
    curl -s -u "$ADMIN_USER:$ADMIN_PASSWORD" http://localhost:5984/_membership | tee -a "$LOG_FILE"
}

main() {
    log "Установка CouchDB кластера"
    log "Имя узла: $NODE_NAME"
    log "Размер кластера: $CLUSTER_SIZE"
    
    install_couchdb_single
    configure_erlang_cookie
    
    if [ "$CLUSTER_SIZE" -gt 1 ]; then
        setup_cluster
        show_cluster_info
    fi
    
    log "Установка завершена!"
    echo "URL: http://$(hostname -I | awk '{print $1}'):5984/_utils/"
    echo "User: $ADMIN_USER"
    echo "Password: $ADMIN_PASSWORD"
}

main
