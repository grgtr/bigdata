# Развертывание YARN на кластере Hadoop

В этом руководстве описаны шаги по настройке и запуску YARN (ResourceManager, NodeManager) и HistoryServer на кластере Hadoop. Предполагается, что HDFS уже настроена и работает, а все узлы доступны по SSH без пароля.

## Предварительные требования

- Кластер Hadoop (NameNode, DataNode'ы) развернут и функционирует.
- Пользователь `hadoop` имеет одинаковые домашние каталоги на всех узлах.
- Настроен SSH-доступ с NameNode на все узлы без пароля.
- Переменные окружения (JAVA_HOME, HADOOP_HOME) заданы корректно (например, в `~/.profile`).

## Шаги развертывания

### 1. Создание конфигурационных файлов

На **NameNode** отредактируйте следующие файлы в каталоге `$HADOOP_HOME/etc/hadoop/`:

- **`mapred-site.xml`** — указывает использовать YARN в качестве фреймворка выполнения:
  ```xml
  <configuration>
      <property>
          <name>mapreduce.framework.name</name>
          <value>yarn</value>
      </property>
      <property>
          <name>mapreduce.application.classpath</name>
          <value>$HADOOP_HOME/share/hadoop/mapreduce/*:$HADOOP_HOME/share/hadoop/mapreduce/lib/*</value>
      </property>
  </configuration>
  ```

- **`yarn-site.xml`** — основные настройки YARN:
  ```xml
  <configuration>
      <property>
          <name>yarn.nodemanager.aux-services</name>
          <value>mapreduce_shuffle</value>
      </property>
      <property>
          <name>yarn.nodemanager.env-whitelist</name>
          <value>JAVA_HOME,HADOOP_COMMON_HOME,HADOOP_HDFS_HOME,HADOOP_CONF_DIR,CLASSPATH_PREPEND_DISTCACHE,HADOOP_YARN_HOME,HADOOP_HOME,PATH,LANG,TZ,HADOOP_MAPRED_HOME</value>
      </property>
      <property>
          <name>yarn.resourcemanager.hostname</name>
          <value>192.168.10.19</value>  <!-- IP или имя NameNode -->
      </property>
  </configuration>
  ```

- **`workers`**— список узлов, на которых будут запущены NodeManager:
  ```
  192.168.10.19
  192.168.10.17
  192.168.10.18
  ```

### 2. Распространение конфигурации на все узлы

```bash
cd $HADOOP_HOME/etc/hadoop
for node in 192.168.10.17 192.168.10.18; do
    scp mapred-site.xml yarn-site.xml workers $node:$HADOOP_HOME/etc/hadoop/
done
```

### 3. Запуск YARN и HistoryServer

На NameNode выполните:

```bash
$HADOOP_HOME/sbin/start-yarn.sh      # запуск ResourceManager и NodeManager на всех узлах из workers
$HADOOP_HOME/bin/mapred --daemon start historyserver   # запуск HistoryServer
```

### 4. Проверка запущенных сервисов

- **NameNode (192.168.10.19)**:
  ```
  jps | grep -E 'NameNode|DataNode|SecondaryNameNode|ResourceManager|NodeManager|JobHistoryServer'
  ```

- **DataNode'ы (192.168.10.17, 192.168.10.18)**:
  ```
  jps | grep -E 'DataNode|NodeManager'
  ```

## Доступ к веб-интерфейсам через SSH-туннель

Для внешнего доступа к веб-интерфейсам кластера используйте SSH-туннелирование через jump node (публичный сервер). Порты по умолчанию:

- **NameNode Web UI** — порт `9870`
- **ResourceManager Web UI** — порт `8088`
- **JobHistoryServer Web UI** — порт `19888`

```bash
ssh -L 9870:192.168.10.19:9870 -L 8088:192.168.10.19:8088 -L 19888:192.168.10.19:19888 ubuntu@178.236.25.101
```

После выполнения команды вы сможете открыть в браузере на локальной машине:

- http://localhost:9870 — интерфейс NameNode
- http://localhost:8088 — интерфейс ResourceManager
- http://localhost:19888 — интерфейс JobHistoryServer

