# Оркестрация обработки данных с Apache Spark на YARN с использованием Prefect

## Цель работы

Реализовать автоматизированный ETL-процесс обработки данных с использованием Apache Spark под управлением YARN, интегрированный с Hive, и оркестрированный с помощью Prefect. Задача включает:

- Запуск Spark-сессии на YARN
- Чтение данных из HDFS
- Трансформации и агрегации
- Сохранение результата в партиционированную таблицу Hive
- Проверку результатов через Hive

## Архитектура и компоненты

| Компонент | Роль | Узел |
|-----------|------|------|
| **HDFS NameNode** | Хранение исходных и результирующих данных | `192.168.10.19` |
| **YARN ResourceManager** | Управление ресурсами для Spark | `192.168.10.19` |
| **YARN NodeManager** | Выполнение контейнеров | `192.168.10.19`, `192.168.10.17`, `192.168.10.18` |
| **Hive Metastore / HiveServer2** | Хранение метаданных, доступ к таблицам | `192.168.10.19` |
| **Spark (3.5.0)** | Вычислительный движок | Установлен на `192.168.10.19` |
| **Prefect** | Оркестрация задач | `192.168.10.55` (jump node) |

## Предварительные требования

- Кластер Hadoop (HDFS, YARN) развёрнут и работает.
- Hive установлен, настроен и доступен через HiveServer2 (порт 5433).
- Spark установлен и настроен для работы с YARN (скрипт `install_spark.sh` из репозитория).
- Исходные данные загружены в HDFS: `/user/hadoop/sales_data/data.csv` (формат: `sale_date,product_id,quantity,category,amount`).
- На jump node установлен Prefect (Python 3.12).

## Реализация

### 1. Создание Prefect flow

Файл `sales_flow_async.py` содержит асинхронный flow, который выполняет две задачи:

1. **run_spark_job** – запускает на NameNode скрипт `run_spark.sh` (который, в свою очередь, вызывает `spark_job.py` с параметрами YARN).
2. **verify_result** – запускает скрипт `verify_hive.sh` для проверки создания таблицы и данных.

```python
from prefect import flow, task
from prefect_shell import shell_run_command

@task
async def run_spark_job():
    result = await shell_run_command(
        command="cd /home/hadoop/hw2 && ./run_spark.sh",
        return_all=True
    )
    return result

@task
async def verify_result():
    result = await shell_run_command(
        command="/home/hadoop/hw2/verify_hive.sh",
        return_all=True
    )
    return result

@flow(name="spark_sales_processing")
async def sales_flow():
    await run_spark_job()
    await verify_result()

if __name__ == "__main__":
    import asyncio
    asyncio.run(sales_flow())
```

### 2. Spark-задача (spark_job.py)

Основные этапы:
- Чтение CSV из HDFS с заданной схемой.
- Добавление вычисляемых полей: `total_value = quantity * amount`, `year`, `month`, `day`.
- Группировка по `category`, `sale_date` с агрегацией: сумма выручки, сумма количества, число продуктов, средняя цена.
- Сохранение результата в формате Parquet с партиционированием по `sale_date` в каталог `/user/hadoop/sales_analytics`.
- Создание внешней таблицы Hive через `beeline`:
  - База данных `spark_demo`
  - Таблица `sales_analytics`
  - Расположение данных: `hdfs://192.168.10.19:9000/user/hadoop/sales_analytics`
- Выполнение `MSCK REPAIR TABLE` для регистрации партиций.

### 3. Скрипт проверки (verify_hive.sh)

Использует `beeline` для выполнения запросов:
- `SHOW DATABASES;`
- `USE spark_demo;`
- `SHOW TABLES;`
- `DESCRIBE FORMATTED sales_analytics;`
- `SELECT * FROM sales_analytics ORDER BY sale_date, category;`

Также проверяет содержимое HDFS по пути `/user/hadoop/sales_analytics` и выводит последние успешные YARN-приложения.

## Результат выполнения

При запуске flow:

```bash
python3 sales_flow_async.py
```

- Spark-приложение (ID `application_..._0011`) запустилось на YARN и успешно завершилось.
- Данные прочитаны, трансформированы, агрегированы.
- Партиции сохранены в HDFS:

```
/user/hadoop/sales_analytics/
├── sale_date=2025-03-14/
│   └── part-00000-...snappy.parquet
├── sale_date=2025-03-15/
│   └── part-00000-...snappy.parquet
└── sale_date=2025-03-16/
    └── part-00000-...snappy.parquet
```

- Внешняя таблица Hive создана и содержит партиции.
- Проверка через Hive показала ожидаемые данные:

| category    | total_revenue | total_quantity | num_products | avg_amount | sale_date  |
|-------------|---------------|----------------|--------------|------------|------------|
| clothing    | 269997.0      | 300.0          | 1            | 899.99     | 2025-03-14 |
| electronics | 313312.875    | 250.5          | 1            | 1250.75    | 2025-03-14 |
| books       | 67875.1875    | 150.75         | 1            | 450.25     | 2025-03-15 |
| electronics | 882000.0      | 420.0          | 1            | 2100.0     | 2025-03-15 |
| clothing    | 28275.2       | 75.2           | 1            | 376.0      | 2025-03-16 |

- В YARN ResourceManager UI видны выполненные приложения, в Spark History Server – детали выполнения.

## Заключение

Разработанный пайплайн демонстрирует полную автоматизацию обработки данных с использованием Apache Spark на YARN под управлением Prefect. Все этапы (чтение, трансформация, запись, регистрация в Hive) выполняются последовательно, с возможностью мониторинга и повторного запуска. Полученная таблица доступна для аналитики через Hive.

---

## Ссылки на исходные файлы

- [spark_job.py](https://github.com/grgtr/bigdata/blob/main/hw4/spark_job.py)
- [run_spark.sh](https://github.com/grgtr/bigdata/blob/main/hw4/run_spark.sh)
- [verify_hive.sh](https://github.com/grgtr/bigdata/blob/main/hw4/verify_hive.sh)
- [install_spark.sh](https://github.com/grgtr/bigdata/blob/main/hw4/install_spark.sh)
- [sales_flow_async.py](https://github.com/grgtr/bigdata/blob/main/hw4/sales_flow_async.py) (создан в рамках задания)
