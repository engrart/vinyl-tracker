// eslint-disable-next-line no-unused-vars
function errorHandler(err, req, res, next) {
  // JWT / auth errors (express-jwt throws these)
  if (err.name === 'UnauthorizedError') {
    return res.status(401).json({ error: 'Invalid or missing token' });
  }

  // Postgres: unique violation
  if (err.code === '23505') {
    return res.status(409).json({ error: 'Duplicate entry', detail: err.detail });
  }
  // Postgres: invalid UUID
  if (err.code === '22P02') {
    return res.status(400).json({ error: 'Invalid ID format' });
  }
  // Postgres: FK violation
  if (err.code === '23503') {
    return res.status(400).json({ error: 'Referenced resource does not exist' });
  }

  // Multer file size limit
  if (err.code === 'LIMIT_FILE_SIZE') {
    return res.status(413).json({ error: 'Image too large (max 10 MB)' });
  }

  console.error('[error]', err);
  res.status(500).json({ error: 'Internal server error' });
}

module.exports = errorHandler;
