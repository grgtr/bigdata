# HDFS Cluster Setup

# Hadoop HDFS Cluster Automated Deployment

Автоматическая развертка HDFS кластера с 3 DataNode, NameNode, и Secondary NameNode.

## Architecture

- **NameNode**: 192.168.10.19 (team-04-nn)
- **Secondary NameNode**: 192.168.10.55 (team-04-jn)
- **DataNode 1**: 192.168.10.17 (team-04-dn-00)
- **DataNode 2**: 192.168.10.18 (team-04-dn-01)
- **DataNode 3**: 192.168.10.19 (team-04-nn)

## Prerequisites

### Manual Setup Required

1. **SSH Access**: Configure SSH key access from local machine to jump node (team-04-jn)
   ```bash
   # Локально ~/.ssh/config
   Host bigdata
       HostName 178.236.25.101
       User ubuntu
       IdentityFile ~/.ssh/id_ed25519_bigdata
2. Поставил env:
HADOOP_PASS="hadoop123"
UBUNTU_PASS=########

## Deploy
```bash
chmod +x setup.sh
./setup.sh
```

Про стейджи setup.sh:

```bash
create_user_local          # Создание пользователя hadoop на jn-ноде
create_user_remote         # Создание пользователя hadoop на nn, dn-00, dn-01
set_hadoop_password        # Установка пароля для hadoop на всех нодах
setup_ssh_local            # Генерация SSH ключей на jn и настройка локального доступа
setup_ssh_remote           # Копирование ключей на nn, dn-00, dn-01 для беспарольного доступа
install_java               # Установка OpenJDK-8 на всех нодах
install_hadoop             # Скачивание Hadoop на jn, копирование на остальные ноды
configure_env              # Настройка переменных окружения JAVA_HOME, HADOOP_HOME на всех нодах
configure_hadoop           # Создание core-site.xml, hdfs-site.xml, workers на всех нодах
update_hosts               # Добавление hostname маппинга в /etc/hosts на всех нодах
start_cluster              # Форматирование NameNode и запуск HDFS на nn
verify                     # Проверка процессов (jps) и статуса кластера (hdfs dfsadmin -report)
```

## Checking:

1.  Связываем 192.168.10.19:9870/9868 с нашим http://localhost:19870 и http://localhost:19868 командой
```bash
ssh -L 19870:192.168.10.19:9870 -L 19868:192.168.10.55:9868 ubuntu@178.236.25.101
```
В котором видим:

    Overview таб:
        Live Nodes: 3
        Dead Nodes: 0
        Under-Replicated Blocks: 0

    Datanodes таб:
        Должны быть все 3 ноды в статусе In Service (зеленые)
        192.168.10.17 (dn00)
        192.168.10.18 (dn01)
        192.168.10.19 (nn)

2. Либо:
```bash
$ ./hw1/verify.sh 
```
Будет примерно такой лог:
```bash
=== Checking cluster processes ===
NameNode:
[sudo] password for ubuntu: 
45280 NameNode
Secondary NameNode:
110893 SecondaryNameNode
DataNodes:
  192.168.10.17:
43344 DataNode
  192.168.10.18:
38444 DataNode
  192.168.10.19:
45452 DataNode

=== HDFS Report ===
Configured Capacity: 157555261440 (146.73 GB)
Present Capacity: 114987364352 (107.09 GB)
DFS Remaining: 114987204608 (107.09 GB)
DFS Used: 159744 (156 KB)
DFS Used%: 0.00%
Replicated Blocks:
        Under replicated blocks: 0
        Blocks with corrupt replicas: 0
        Missing blocks: 0
        Missing blocks (with replication factor 1): 0
        Low redundancy blocks with highest priority to recover: 0
        Pending deletion blocks: 0
Erasure Coded Block Groups: 
        Low redundancy block groups: 0
        Block groups with corrupt internal blocks: 0
        Missing block groups: 0
        Low redundancy blocks with highest priority to recover: 0
        Pending deletion blocks: 0

-------------------------------------------------
Live datanodes (3):

Name: 192.168.10.17:9866 (dn00)
Hostname: team-04-dn-00
Decommission Status : Normal
Configured Capacity: 52518420480 (48.91 GB)
DFS Used: 53248 (52 KB)
Non DFS Used: 11560386560 (10.77 GB)
DFS Remaining: 38257008640 (35.63 GB)
DFS Used%: 0.00%

=== Test HDFS operations ===
Welcome to Ubuntu 24.04.4 LTS (GNU/Linux 6.8.0-100-generic x86_64)

 * Documentation:  https://help.ubuntu.com
 * Management:     https://landscape.canonical.com
 * Support:        https://ubuntu.com/pro

 System information as of Wed Feb 25 08:48:44 PM UTC 2026

  System load:  0.0                Processes:               167
  Usage of /:   22.1% of 48.91GB   Users logged in:         1
  Memory usage: 28%                IPv4 address for ens160: 192.168.10.19
  Swap usage:   0%

 * Strictly confined Kubernetes makes edge and IoT secure. Learn how MicroK8s
   just raised the bar for easy, resilient and secure K8s cluster deployment.

   https://ubuntu.com/engage/secure-kubernetes-at-the-edge

Expanded Security Maintenance for Applications is not enabled.

12 updates can be applied immediately.
4 of these updates are standard security updates.
To see these additional updates run: apt list --upgradable

Enable ESM Apps to receive additional future security updates.
See https://ubuntu.com/esm or run: sudo pro status


*** System restart required ***
test
✓ HDFS read/write OK

=== Web UI ===
NameNode: http://192.168.10.19:9870
Secondary NameNode: http://192.168.10.55:9868
```

