const { Router } = require('express');
const { master, slave } = require('../db');

const router = Router();

// POST /products — write to master
router.post('/', async (req, res) => {
  const { name, price } = req.body;

  if (!name || typeof name !== 'string' || name.trim() === '') {
    return res.status(400).json({ error: 'name is required and must be a non-empty string' });
  }

  const parsed = parseFloat(price);
  if (price === undefined || price === null || isNaN(parsed) || parsed < 0) {
    return res.status(400).json({ error: 'price is required and must be a non-negative number' });
  }

  const [result] = await master.execute(
    'INSERT INTO products (name, price) VALUES (?, ?)',
    [name.trim(), parsed]
  );

  res.status(201).json({
    message: 'Product created',
    data: { id: result.insertId, name: name.trim(), price: parsed },
  });
});

// GET /products — read from slave
router.get('/', async (req, res) => {
  const [rows] = await slave.execute('SELECT id, name, price FROM products');

  res.json({
    metadata: { processed_by: process.env.SERVER_ID || 'unknown' },
    data: rows,
  });
});

module.exports = router;
