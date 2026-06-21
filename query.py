import duckdb
import sys

con = duckdb.connect('mrr_analytics.duckdb', read_only=True)
sql = " ".join(sys.argv[1:]) if len(sys.argv) > 1 else "SHOW TABLES"
print(con.sql(sql).df().to_string())
con.close()
