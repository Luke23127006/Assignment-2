require('dotenv').config();
const mysql = require('mysql2/promise');

const base = {
  port    : process.env.DB_PORT     || 3306,
  user    : process.env.DB_USER     || 'root',
  password: process.env.DB_PASSWORD || '',
  database: process.env.DB_NAME     || 'appdb',
};

const master = mysql.createPool({ ...base, host: process.env.DB_MASTER_HOST || 'db_master' });
const slave  = mysql.createPool({ ...base, host: process.env.DB_SLAVE_HOST  || 'db_slave'  });

module.exports = { master, slave };
