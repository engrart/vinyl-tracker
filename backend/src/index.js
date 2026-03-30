require('dotenv').config();

const express = require('express');
const helmet = require('helmet');
const cors = require('cors');
const rateLimit = require('express-rate-limit');

const auth = require('./middleware/auth');
const errorHandler = require('./middleware/errorHandler');
const recordsRouter = require('./routes/records');

const app = express();

// ── Security headers ─────────────────────────────────────────────────────────
app.use(helmet());
app.use(cors({
  origin: process.env.CORS_ORIGIN || '*',
  methods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS'],
  allowedHeaders: ['Content-Type', 'Authorization'],
}));

// ── Body parsing ─────────────────────────────────────────────────────────────
app.use(express.json({ limit: '1mb' }));

// ── Rate limiting ─────────────────────────────────────────────────────────────
app.use('/v1', rateLimit({
  windowMs: 15 * 60 * 1000, // 15 min
  max: 200,
  standardHeaders: true,
  legacyHeaders: false,
  message: { error: 'Too many requests — please slow down.' },
}));

// ── Health check (no auth) ────────────────────────────────────────────────────
app.get('/health', (_req, res) =>
  res.json({ status: 'ok', ts: new Date().toISOString() })
);

// ── API routes (all require Bearer JWT) ──────────────────────────────────────
app.use('/v1', auth);
app.use('/v1/records', recordsRouter);

// ── Error handler ─────────────────────────────────────────────────────────────
app.use(errorHandler);

// ── Start ─────────────────────────────────────────────────────────────────────
const PORT = parseInt(process.env.PORT || '3000', 10);
app.listen(PORT, () =>
  console.log(`VinylTracker API listening on port ${PORT} [${process.env.NODE_ENV || 'development'}]`)
);
