```bash
#!/bin/bash
set -euo pipefail  # строгий режим: прерывание при ошибке, неопределённых переменных, ошибках в пайпах

HIVE_VERSION="4.0.0-alpha-2"
HIVE_TAR="apache-hive-${HIVE_VERSION}-bin.tar.gz"
HIVE_DOWNLOAD_URL="https://archive.apache.org/dist/hive/hive-${HIVE_VERSION}/${HIVE_TAR}"
HIVE_HOME="/home/hadoop/apache-hive-${HIVE_VERSION}-bin"
JDBC_DRIVER_URL="https://jdbc.postgresql.org/download/postgresql-42.7.4.jar"
JDBC_JAR="postgresql-42.7.4.jar"

# Узлы кластера
NN_IP="192.168.10.19"          # NameNode (узел, где будет HiveServer2)
DN01_IP="192.168.10.17"         # DataNode с PostgreSQL
JN_IP="192.168.10.55"           # Jump node (для доступа к веб-интерфейсам)

# Параметры PostgreSQL
PG_DB="metastore"
PG_USER="hive"
PG_PASSWORD="hiveMegaPass"
PG_HOST="$DN01_IP"
PG_PORT="5432"

remote_exec() {
    local node=$1
    shift
    ssh -t "hadoop@$node" "$@"
}

echo ">>> Настройка PostgreSQL на $DN01_IP"

remote_exec "$DN01_IP" "
    set -e
    if ! dpkg -l | grep -q postgresql-16; then
        echo 'Установка PostgreSQL...'
        sudo apt update
        sudo apt install -y postgresql-16
    else
        echo 'PostgreSQL уже установлен.'
    fi
    sudo systemctl enable postgresql
    sudo systemctl start postgresql
"

remote_exec "$DN01_IP" "
    set -e
    # Проверяем, существует ли база данных
    if ! sudo -u postgres psql -tAc \"SELECT 1 FROM pg_database WHERE datname='$PG_DB'\" | grep -q 1; then
        echo 'Создание базы данных и пользователя...'
        sudo -u postgres psql <<EOF
CREATE USER $PG_USER WITH PASSWORD '$PG_PASSWORD';
CREATE DATABASE $PG_DB;
GRANT ALL PRIVILEGES ON DATABASE $PG_DB TO $PG_USER;
ALTER DATABASE $PG_DB OWNER TO $PG_USER;
EOF
    else
        echo 'База данных $PG_DB уже существует.'
    fi
"

# Настройка postgresql.conf
remote_exec "$DN01_IP" "
    set -e
    PG_CONF=\$(sudo -u postgres psql -tAc \"SHOW config_file\")
    sudo sed -i \"s/^#listen_addresses = 'localhost'/listen_addresses = '$DN01_IP'/\" \$PG_CONF
    sudo sed -i \"s/^listen_addresses = .*/listen_addresses = '$DN01_IP'/\" \$PG_CONF
"

# Настройка pg_hba.conf (добавляем правила для nn и jn)
remote_exec "$DN01_IP" "
    set -e
    PG_HBA=\$(sudo -u postgres psql -tAc \"SHOW hba_file\")

    sudo sed -i '/host.*$PG_DB.*$PG_USER/d' \$PG_HBA
    # Добавляем новые правила
    echo \"host    $PG_DB    $PG_USER    $NN_IP/32        password\" | sudo tee -a \$PG_HBA
    echo \"host    $PG_DB    $PG_USER    $JN_IP/32        password\" | sudo tee -a \$PG_HBA
"

remote_exec "$DN01_IP" "sudo systemctl restart postgresql"

echo ">>> Установка PostgreSQL клиента на nn"
if ! command -v psql &> /dev/null; then
    sudo apt install -y postgresql-client-16
fi

echo ">>> Проверка подключения к PostgreSQL с nn"
PGPASSWORD="$PG_PASSWORD" psql -h "$PG_HOST" -p "$PG_PORT" -U "$PG_USER" -d "$PG_DB" -c "SELECT 1" > /dev/null 2>&1 || {
    echo "Ошибка: не удалось подключиться к PostgreSQL. Проверьте настройки."
    exit 1
}
echo "Подключение к PostgreSQL успешно."

echo ">>> Установка Hive на nn"


if [ ! -d "$HIVE_HOME" ]; then
    echo "Скачивание Hive $HIVE_VERSION ..."
    wget -q "$HIVE_DOWNLOAD_URL" -O "/tmp/$HIVE_TAR"
    tar -xzf "/tmp/$HIVE_TAR" -C /home/hadoop/
    rm "/tmp/$HIVE_TAR"
else
    echo "Hive уже установлен в $HIVE_HOME"
fi

if ! grep -q "HIVE_HOME" ~/.profile; then
    echo "Добавление переменных окружения Hive в ~/.profile"
    cat >> ~/.profile <<EOF

# Hive
export HIVE_HOME=$HIVE_HOME
export HIVE_CONF_DIR=\$HIVE_HOME/conf
export HIVE_AUX_JARS_PATH=\$HIVE_HOME/lib/*
export PATH=\$PATH:\$HIVE_HOME/bin
EOF
    source ~/.profile
else
    echo "Переменные Hive уже присутствуют в ~/.profile"
fi

# Создание hive-site.xml
echo "Создание $HIVE_HOME/conf/hive-site.xml"
cat > "$HIVE_HOME/conf/hive-site.xml" <<EOF
<configuration>
    <property>
        <name>hive.server2.authentication</name>
        <value>NONE</value>
    </property>
    <property>
        <name>hive.metastore.warehouse.dir</name>
        <value>/user/hive/warehouse</value>
    </property>
    <property>
        <name>hive.server2.thrift.port</name>
        <value>5433</value>
        <description>TCP port number to listen on, default 10000</description>
    </property>
    <property>
        <name>javax.jdo.option.ConnectionURL</name>
        <value>jdbc:postgresql://$PG_HOST:$PG_PORT/$PG_DB</value>
    </property>
    <property>
        <name>javax.jdo.option.ConnectionDriverName</name>
        <value>org.postgresql.Driver</value>
    </property>
    <property>
        <name>javax.jdo.option.ConnectionUserName</name>
        <value>$PG_USER</value>
    </property>
    <property>
        <name>javax.jdo.option.ConnectionPassword</name>
        <value>$PG_PASSWORD</value>
    </property>
    <!-- Для веб-интерфейса HiveServer2 -->
    <property>
        <name>hive.server2.webui.host</name>
        <value>0.0.0.0</value>
    </property>
    <property>
        <name>hive.server2.webui.port</name>
        <value>10002</value>
    </property>
</configuration>
EOF

# Загрузка JDBC драйвера
if [ ! -f "$HIVE_HOME/lib/$JDBC_JAR" ]; then
    echo "Скачивание JDBC драйвера PostgreSQL..."
    wget -q "$JDBC_DRIVER_URL" -O "/tmp/$JDBC_JAR"
    cp "/tmp/$JDBC_JAR" "$HIVE_HOME/lib/"
    rm "/tmp/$JDBC_JAR"
else
    echo "JDBC драйвер уже присутствует в lib/"
fi


echo ">>> Создание каталогов в HDFS"
hdfs dfs -mkdir -p /user/hive/warehouse
hdfs dfs -chmod g+w /tmp
hdfs dfs -chmod g+w /user/hive/warehouse

echo ">>> Инициализация схемы метастор"
# Проверяем, инициализирована ли уже схема (например, по наличию таблицы VERSION)
if ! "$HIVE_HOME/bin/schematool" -dbType postgres -info > /dev/null 2>&1; then
    "$HIVE_HOME/bin/schematool" -dbType postgres -initSchema
    echo "Схема инициализирована."
else
    echo "Схема метастор уже инициализирована."
fi

echo ">>> Запуск HiveServer2 в фоне"
if pgrep -f "org.apache.hive.service.server.HiveServer2" > /dev/null; then
    echo "HiveServer2 уже запущен."
else
    nohup "$HIVE_HOME/bin/hive" --service hiveserver2 >> /tmp/hs2.log 2>&1 &
    echo "HiveServer2 запущен с PID $!"
fi

echo "Развёртывание Hive завершено."
echo "Для подключения используйте: beeline -u jdbc:hive2://$NN_IP:5433 -n hadoop"
echo "Веб-интерфейс HiveServer2: http://$NN_IP:10002 (после проброса туннеля)"

```
