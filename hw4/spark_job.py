from pyspark.sql import SparkSession
from pyspark.sql.functions import col, sum as spark_sum, count, avg, year, month, dayofmonth
from pyspark.sql.types import StructType, StructField, StringType, IntegerType, DoubleType

spark = SparkSession.builder \
    .appName("SalesDataProcessing") \
    .getOrCreate()

schema = StructType([
    StructField("sale_date", StringType(), True),
    StructField("product_id", IntegerType(), True),
    StructField("quantity", DoubleType(), True),
    StructField("category", StringType(), True),
    StructField("amount", DoubleType(), True)
])

print("=== Reading data from HDFS ===")
df = spark.read \
    .option("header", "false") \
    .schema(schema) \
    .csv("hdfs://192.168.10.19:9000/user/hadoop/sales_data/data.csv")

print("=== Original Data ===")
df.show()
df.printSchema()

print("=== Applying Transformations ===")
df_transformed = df \
    .withColumn("total_value", col("quantity") * col("amount")) \
    .withColumn("year", year(col("sale_date"))) \
    .withColumn("month", month(col("sale_date"))) \
    .withColumn("day", dayofmonth(col("sale_date")))

print("=== Transformed Data ===")
df_transformed.show()
df_transformed.printSchema()

print("=== Applying Aggregations ===")
df_aggregated = df_transformed \
    .groupBy("category", "sale_date") \
    .agg(
        spark_sum("total_value").alias("total_revenue"),
        spark_sum("quantity").alias("total_quantity"),
        count("product_id").alias("num_products"),
        avg("amount").alias("avg_amount")
    ) \
    .orderBy("sale_date", "category")

print("=== Aggregated Data ===")
df_aggregated.show()

print("=== Saving with partitioning by sale_date ===")
output_path = "hdfs://192.168.10.19:9000/user/hadoop/sales_analytics"

df_aggregated.write \
    .mode("overwrite") \
    .partitionBy("sale_date") \
    .format("parquet") \
    .save(output_path)

print(f"=== Data saved to {output_path} ===")

print("=== Verifying saved data ===")
df_result = spark.read.parquet(output_path)
df_result.show()
print(f"Total records: {df_result.count()}")

print("=== Checking partitions on HDFS ===")
import subprocess
result = subprocess.run(
    ["hdfs", "dfs", "-ls", "-R", output_path],
    capture_output=True,
    text=True
)
print(result.stdout)

print("=== Creating external Hive table ===")
create_table_sql = f"""
CREATE EXTERNAL TABLE IF NOT EXISTS sales_analytics (
    category STRING,
    total_revenue DOUBLE,
    total_quantity DOUBLE,
    num_products BIGINT,
    avg_amount DOUBLE
)
PARTITIONED BY (sale_date STRING)
STORED AS PARQUET
LOCATION '{output_path}'
"""

hive_cmd = f"~/apache-hive-4.0.0-alpha-2-bin/bin/hive -e \"{create_table_sql}\""
result = subprocess.run(hive_cmd, shell=True, capture_output=True, text=True)
print("Hive table creation output:")
print(result.stdout)
print(result.stderr)

print("=== Repairing partitions ===")
repair_cmd = "~/apache-hive-4.0.0-alpha-2-bin/bin/hive -e 'MSCK REPAIR TABLE sales_analytics'"
result = subprocess.run(repair_cmd, shell=True, capture_output=True, text=True)
print(result.stdout)
print(result.stderr)

spark.stop()
print("=== Job completed successfully ===")
