-- Create application database
CREATE DATABASE IF NOT EXISTS appdb
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci;

USE appdb;

-- Products table
CREATE TABLE IF NOT EXISTS products (
  id    INT          NOT NULL AUTO_INCREMENT,
  name  VARCHAR(255) NOT NULL,
  price DECIMAL(10, 2) NOT NULL,
  PRIMARY KEY (id)
) ENGINE=InnoDB;

-- Dedicated replication user
-- '%' allows the slave to connect from any container IP inside app_net
CREATE USER IF NOT EXISTS 'replicator'@'%' IDENTIFIED WITH mysql_native_password BY 'replicator_password';
GRANT REPLICATION SLAVE ON *.* TO 'replicator'@'%';
FLUSH PRIVILEGES;
