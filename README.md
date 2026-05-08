# System Design Assignment 2
## Scalable Web Application with Load Balancing & MySQL Replication

---

## Table of Contents

1. [System Architecture](#1-system-architecture)
2. [Configuration Snippets](#2-configuration-snippets)
3. [Setup Guide](#3-setup-guide)
4. [API Reference](#4-api-reference)
5. [Verification & Testing](#5-verification--testing)

---

## 1. System Architecture

### Architecture Diagram

![image](docs\architecture_diagram.png)

### Component Responsibilities

| Component | Image | Role |
|---|---|---|
| `load_balancer` | `nginx:latest` | Receives all external traffic on port 8080, distributes to API nodes via Round Robin |
| `api_node_1` / `api_node_2` | Custom Node.js | Stateless REST API; writes go to Master, reads go to Slave |
| `db_master` | `mysql:8` | Single write node; publishes changes via binary log |
| `db_slave` | `mysql:8` | Read-only replica; applies changes from Master via GTID replication |
| `db_gui` | `adminer` | Web-based database management UI (port 8081) |

---

## 2. Configuration Snippets

### 2a. Nginx — Round Robin Upstream & Fast Failover

```nginx
# nginx/nginx.conf

upstream api_servers {
    server api_node_1:3000;   # Docker DNS resolves service names
    server api_node_2:3000;   # Default algorithm: Round Robin
}

server {
    listen 80;

    location / {
        proxy_pass         http://api_servers;
        proxy_http_version 1.1;
        proxy_set_header   Host              $host;
        proxy_set_header   X-Real-IP         $remote_addr;
        proxy_set_header   X-Forwarded-For   $proxy_add_x_forwarded_for;

        # Fast failover: abort and retry on the other node after 2s
        # (default is 60s — responsible for the 60s hang during chaos tests)
        proxy_connect_timeout 2s;
        proxy_send_timeout    2s;
        proxy_read_timeout    2s;
    }
}
```

**Why 2s?** Nginx's default timeout is 60 s. Without this, stopping one API node causes every other request to hang for a full minute before Nginx retries the surviving node. With 2 s timeouts, failover is near-instant.

---

### 2b. Node.js API — Read/Write Splitting via Separate Connection Pools

```js
// api/db.js

const mysql = require('mysql2/promise');

const base = {
  port    : process.env.DB_PORT     || 3306,
  user    : process.env.DB_USER     || 'root',
  password: process.env.DB_PASSWORD || '',
  database: process.env.DB_NAME     || 'appdb',
};

// Writes always go to the Master node
const master = mysql.createPool({ ...base, host: process.env.DB_MASTER_HOST || 'db_master' });

// Reads always go to the Slave node
const slave  = mysql.createPool({ ...base, host: process.env.DB_SLAVE_HOST  || 'db_slave'  });

module.exports = { master, slave };
```

```js
// api/routes/products.js (excerpt)

// POST /products — INSERT executes on the Master
router.post('/', async (req, res) => {
  const [result] = await master.execute(
    'INSERT INTO products (name, price) VALUES (?, ?)',
    [name.trim(), parsed]
  );
  res.status(201).json({ message: 'Product created', data: { id: result.insertId, name, price: parsed } });
});

// GET /products — SELECT executes on the Slave
router.get('/', async (req, res) => {
  const [rows] = await slave.execute('SELECT id, name, price FROM products');
  res.json({
    metadata: { processed_by: process.env.SERVER_ID },  // identifies which API node handled this request
    data: rows,
  });
});
```

**Why two pools?** A single pool pointed at one host would either overload the Master with reads or send writes to the read-only Slave (causing errors). Separating pools at the application layer is the standard pattern for MySQL Master-Slave read/write splitting.

---

### 2c. Docker Compose — Custom Network & Startup Ordering

```yaml
# docker-compose.yml (excerpts)

services:
  # Load balancer waits for both API nodes to start
  load_balancer:
    image: nginx:latest
    ports:
      - "8080:80"
    depends_on:
      - api_node_1
      - api_node_2
    networks:
      - app_net

  # API nodes wait for db_master to pass its healthcheck
  api_node_1:
    build: ./api
    environment:
      SERVER_ID: Node_1
      DB_MASTER_HOST: db_master
      DB_SLAVE_HOST: db_slave
    depends_on:
      db_master:
        condition: service_healthy   # waits for mysqladmin ping to succeed
    networks:
      - app_net

  # db_slave waits for db_master before configuring replication
  db_slave:
    image: mysql:8
    depends_on:
      db_master:
        condition: service_healthy
    networks:
      - app_net

# All containers share one isolated bridge network.
# Service names (db_master, db_slave, api_node_1 …) act as DNS hostnames.
networks:
  app_net:
    driver: bridge
```

**Why `service_healthy` instead of `service_started`?** `service_started` only waits for the container process to launch. MySQL takes additional seconds to initialise its data directory. Using a healthcheck (`mysqladmin ping`) ensures the API nodes never attempt a DB connection before MySQL is actually ready to accept one.

---

## 3. Setup Guide

### Prerequisites

| Tool | Minimum version |
|---|---|
| Docker Desktop | 4.x |
| Docker Compose | v2 (bundled with Docker Desktop) |
| Git | any |
| bash / Git Bash | required to run the test script on Windows |

---

### Step-by-step

**Step 1 — Clone the repository**

```bash
git clone https://github.com/Luke23127006/Software-Design---Assignment-2.git
cd "Assignment 2"
```

**Step 2 — (First run only) Remove any leftover volumes**

If you have previously run this project, old MySQL data volumes will prevent the new configuration (GTID, init scripts) from applying. Wipe them first:

```bash
docker-compose down -v
```

> This is safe to skip on a completely fresh machine.

**Step 3 — Build images and start the entire stack**

```bash
docker-compose up -d --build
```

This single command:
- Builds the custom Node.js API image from `./api`
- Pulls `mysql:8`, `nginx:latest`, and `adminer` if not cached
- Starts all 6 services in dependency order:
  1. `db_master` (waits until healthy)
  2. `db_slave` + `api_node_1` + `api_node_2` (in parallel, after master is healthy)
  3. `load_balancer` + `db_gui` (after API nodes start)

**Step 4 — Verify all containers are running**

```bash
docker-compose ps
```

All services should show `Up` or `healthy`. The slave may take 10–20 seconds to appear.

**Step 5 — Confirm MySQL replication is active**

```bash
docker exec db_slave mysql -uroot -proot_password \
  -e "SHOW REPLICA STATUS\G" | grep -E "Replica_IO_Running|Replica_SQL_Running|Seconds_Behind_Source"
```

Expected output:
```
Replica_IO_Running: Yes
Replica_SQL_Running: Yes
Seconds_Behind_Source: 0
```

**Step 6 — Run the automated replication test**

```bash
bash scripts/test_replication.sh
```

Inserts 3 rows into the Master and confirms they appear on the Slave.

---

## 4. API Reference

Base URL: `http://localhost:8080`

### `POST /products`

Creates a new product on the **Master** database.

**Request body**
```json
{
  "name": "Apple",
  "price": 1.50
}
```

**Validation rules**
- `name` — required, non-empty string
- `price` — required, non-negative number

**Response `201 Created`**
```json
{
  "message": "Product created",
  "data": {
    "id": 1,
    "name": "Apple",
    "price": 1.5
  }
}
```

---

### `GET /products`

Fetches all products from the **Slave** database. The `processed_by` field identifies which API node handled the request, demonstrating Round Robin in action.

**Response `200 OK`**
```json
{
  "metadata": {
    "processed_by": "Node_1"
  },
  "data": [
    { "id": 1, "name": "Apple",  "price": "1.50" },
    { "id": 2, "name": "Banana", "price": "0.75" }
  ]
}
```

---

### `GET /health`

Lightweight liveness check used by the load balancer.

**Response `200 OK`**
```json
{ "status": "ok" }
```

---

## 5. Verification & Testing

### Confirm Round Robin load balancing

Call `GET /products` twice and observe `processed_by` alternating between `Node_1` and `Node_2`:

```bash
curl -s http://localhost:8080/products | grep processed_by
curl -s http://localhost:8080/products | grep processed_by
```

### Chaos test — fast failover

```bash
# Stop one node
docker stop assignment2-api_node_1-1

# All subsequent requests should route to Node_2 within ~2 seconds
curl http://localhost:8080/products

# Restore
docker start assignment2-api_node_1-1
```

### Database GUI (Adminer)

Open `http://localhost:8081` and log in with:

| Field    | Value           |
|----------|-----------------|
| System   | MySQL           |
| Server   | `db_master` or `db_slave` |
| Username | `root`          |
| Password | `root_password` |
| Database | `appdb`         |
