require('dotenv').config();
const express = require('express');
const productsRouter = require('./routes/products');

const app  = express();
const PORT = process.env.PORT || 3000;

app.use(express.json());

app.get('/health', (_req, res) => res.json({ status: 'ok' }));
app.use('/products', productsRouter);

// Centralised error handler — catches any async error thrown in routes
app.use((err, _req, res, _next) => {
  console.error(err);
  res.status(500).json({ error: 'Internal server error' });
});

app.listen(PORT, () => console.log(`API listening on port ${PORT} [${process.env.SERVER_ID}]`));
