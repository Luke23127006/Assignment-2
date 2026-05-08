#!/usr/bin/env bash
# Test MySQL Master → Slave replication.
# Run from the project root after `docker-compose up -d`.
# On Windows: execute via Git Bash or WSL.

set -euo pipefail

MASTER="db_master"
SLAVE="db_slave"
MYSQL_ROOT_PWD="root_password"
DB="appdb"

run_master() { docker exec "$MASTER" mysql -uroot -p"$MYSQL_ROOT_PWD" "$DB" -e "$1" 2>/dev/null; }
run_slave()  { docker exec "$SLAVE"  mysql -uroot -p"$MYSQL_ROOT_PWD" "$DB" -e "$1" 2>/dev/null; }

echo "=== 1. Checking replica status on slave ==="
docker exec "$SLAVE" mysql -uroot -p"$MYSQL_ROOT_PWD" \
  -e "SHOW REPLICA STATUS\G" 2>/dev/null \
  | grep -E "Replica_IO_Running|Replica_SQL_Running|Seconds_Behind_Source"

echo ""
echo "=== 2. Inserting test rows into MASTER ==="
run_master "INSERT INTO products (name, price) VALUES ('Apple', 1.50), ('Banana', 0.75), ('Cherry', 3.00);"
echo "Inserted 3 rows."

echo ""
echo "=== 3. Waiting 3 s for replication to propagate ==="
sleep 3

echo ""
echo "=== 4. Reading from SLAVE ==="
run_slave "SELECT * FROM products;"

echo ""
echo "=== 5. Row count comparison ==="
master_count=$(run_master "SELECT COUNT(*) AS c FROM products;" | tail -1)
slave_count=$(run_slave  "SELECT COUNT(*) AS c FROM products;" | tail -1)

echo "  Master rows : $master_count"
echo "  Slave rows  : $slave_count"

if [ "$master_count" = "$slave_count" ]; then
  echo ""
  echo "PASS — slave is in sync with master."
else
  echo ""
  echo "FAIL — row counts differ. Check SHOW REPLICA STATUS on the slave."
  exit 1
fi
