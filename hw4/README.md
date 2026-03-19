# Apache Spark on YARN - Sales Data Processing

Обработка данных с использованием Apache Spark под управлением YARN с сохранением результатов в Hive.

## Архитектура

- **YARN ResourceManager**: 192.168.10.19 (team-04-nn)
- **YARN NodeManagers**: 192.168.10.19, 192.168.10.17, 192.168.10.18
- **HDFS NameNode**: 192.168.10.19
- **Hive Metastore & HiveServer2**: 192.168.10.19
- **Spark**: 3.5.0
- **Hive**: 4.0.0-alpha-2

## Предварительные требования

- Работающий HDFS кластер (из hw1)
- Работающий YARN кластер
- Hive установлен и настроен
- Исходные данные в HDFS: `/user/hadoop/sales_data/data.csv`

### Формат исходных данных

```csv
sale_date,product_id,quantity,category,amount
2025-03-14,101,250.5,electronics,1250.75
2025-03-14,102,300.0,clothing,899.99
2025-03-15,103,150.75,books,450.25
2025-03-15,104,420.0,electronics,2100.00
2025-03-16,105,75.2,clothing,376.00
```

## Установка и настройка

### 1. Установка Spark

На jump-ноде (team-04-jn):

```bash
cd ~/hw2
chmod +x install_spark.sh
./install_spark.sh
```

Скрипт выполняет:
- Скачивание Spark 3.5.0
- Настройка для работы с YARN
- Интеграция с Hive Metastore
- Копирование Hive JAR библиотек
- Создание директории для логов в HDFS
- Запуск Spark History Server

### 2. Запуск обработки данных

```bash
chmod +x run_spark.sh
./run_spark.sh
```

## Описание обработки данных

### Трансформации

1. **Добавление вычисляемых полей**:
   - `total_value = quantity * amount`
   - `year = year(sale_date)`
   - `month = month(sale_date)`
   - `day = dayofmonth(sale_date)`

2. **Приведение типов**:
   - `product_id`: String → Integer
   - `quantity`: String → Double
   - `amount`: String → Double

### Агрегации

Группировка по `category` и `sale_date` с вычислением:
- `total_revenue = SUM(total_value)` - общая выручка
- `total_quantity = SUM(quantity)` - общее количество
- `num_products = COUNT(product_id)` - количество продуктов
- `avg_amount = AVG(amount)` - средняя цена

### Партиционирование

Данные партиционированы по полю `sale_date`:
```
/user/hadoop/sales_analytics/
├── sale_date=2025-03-14/
│   └── part-00000-*.snappy.parquet
├── sale_date=2025-03-15/
│   └── part-00000-*.snappy.parquet
└── sale_date=2025-03-16/
    └── part-00000-*.snappy.parquet
```

### Сохранение результатов

Данные сохранены в формате **Parquet** с внешней Hive таблицей:
- База данных: `spark_demo`
- Таблица: `sales_analytics`
- Формат: Parquet (сжатие Snappy)
- Расположение: `/user/hadoop/sales_analytics`

## Проверка результатов

### Через Hive CLI

На NameNode:

```bash
ssh hadoop@192.168.10.19
~/apache-hive-4.0.0-alpha-2-bin/bin/beeline -u "jdbc:hive2://localhost:5433" -n hadoop
```

В Hive:

```sql
USE spark_demo;

SHOW TABLES;

SELECT * FROM sales_analytics ORDER BY sale_date, category;

SHOW PARTITIONS sales_analytics;

DESCRIBE FORMATTED sales_analytics;
```

### Ожидаемый результат

```
+-------------+----------------+-----------------+---------------+-------------+------------+
| category    | total_revenue  | total_quantity  | num_products  | avg_amount  | sale_date  |
+-------------+----------------+-----------------+---------------+-------------+------------+
| clothing    | 269997.0       | 300.0           | 1             | 899.99      | 2025-03-14 |
| electronics | 313312.875     | 250.5           | 1             | 1250.75     | 2025-03-14 |
| books       | 67875.1875     | 150.75          | 1             | 450.25      | 2025-03-15 |
| electronics | 882000.0       | 420.0           | 1             | 2100.0      | 2025-03-15 |
| clothing    | 28275.2        | 75.2            | 1             | 376.0       | 2025-03-16 |
+-------------+----------------+-----------------+---------------+-------------+------------+
```

### Проверка на HDFS

```bash
~/hadoop/bin/hdfs dfs -ls -R /user/hadoop/sales_analytics/
```

### Автоматическая проверка

```bash
chmod +x verify_hive.sh
./verify_hive.sh
```

## Web UI

Доступ через SSH tunnel с локальной машины:

```bash
ssh -L 8088:192.168.10.19:8088 -L 18080:192.168.10.19:18080 ubuntu@178.236.25.101
```

- **YARN ResourceManager**: http://localhost:8088
- **Spark History Server**: http://localhost:18080

## Выполнение требований задания

+ **Запуск Spark под управлением YARN** - используется `--master yarn --deploy-mode client`
+ **Подключение к HDFS** - чтение из `hdfs://192.168.10.19:9000/user/hadoop/sales_data/`
+ **Чтение данных** - CSV файл загружен через `spark.read.csv()`
+ **Трансформации данных**:
  - Вычисляемое поле `total_value`
  - Извлечение компонентов даты (`year`, `month`, `day`)
  - Приведение типов данных
+ **Агрегации**:
  - `SUM()` для revenue и quantity
  - `COUNT()` для подсчета продуктов
  - `AVG()` для средней цены
+ **Партиционирование** - данные разделены по `sale_date`
+ **Сохранение как таблица** - создана внешняя Hive таблица `sales_analytics`
+ **Чтение через Hive** - данные успешно читаются стандартным клиентом `beeline`

## Структура файлов

```
hw2/
├── install_spark.sh    # Установка и настройка Spark
├── spark_job.py        # PySpark ETL скрипт
├── run_spark.sh        # Запуск Spark job на YARN
├── verify_hive.sh      # Проверка результатов в Hive
└── README.md           # Документация
```

## Логи и мониторинг

- **Spark Application ID**: `application_1773484318682_*`
- **YARN Job Tracking**: http://localhost:8088/cluster/apps
- **Spark History**: http://localhost:18080
- **HDFS Location**: `/user/hadoop/sales_analytics/`

## Остановка сервисов

```bash
# Остановить Spark History Server
ssh hadoop@192.168.10.19 "~/spark/sbin/stop-history-server.sh"

# Остановить HiveServer2 (если нужно)
ssh hadoop@192.168.10.19 "pkill -f hiveserver2"
```
