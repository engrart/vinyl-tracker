const router = require('express').Router();
const multer = require('multer');
const pool = require('../db');
const { lookup } = require('../services/musicbrainz');
const { uploadImage } = require('../services/storage');

const upload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: 10 * 1024 * 1024 }, // 10 MB
});

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Upsert the user row keyed by Clerk/Auth0 sub, returning our internal UUID.
 * On every authenticated request we ensure the user exists — zero-friction
 * onboarding; no separate "register" endpoint needed.
 */
async function resolveUserId(req) {
  const clerkUserId = req.auth.sub;
  // Auth0 puts email in the token; Clerk puts it in a custom claim or separate
  // endpoint. Accept either common claim name.
  const email =
    req.auth.email ||
    req.auth['https://vinyltracker.app/email'] ||
    '';

  const { rows } = await pool.query(
    `INSERT INTO users (clerk_user_id, email)
     VALUES ($1, $2)
     ON CONFLICT (clerk_user_id)
     DO UPDATE SET email = EXCLUDED.email
     RETURNING id`,
    [clerkUserId, email]
  );
  return rows[0].id;
}

const ALLOWED_SORT  = new Set(['date_added', 'title', 'artist', 'year', 'created_at']);
const ALLOWED_ORDER = new Set(['asc', 'desc']);

// ─────────────────────────────────────────────────────────────────────────────
// GET /v1/records
// Query params: search, genre, sort, order
// ─────────────────────────────────────────────────────────────────────────────
router.get('/', async (req, res, next) => {
  try {
    const userId = await resolveUserId(req);
    const { search, genre, sort = 'date_added', order = 'desc' } = req.query;

    const safeSort  = ALLOWED_SORT.has(sort)   ? sort  : 'date_added';
    const safeOrder = ALLOWED_ORDER.has(order)  ? order : 'desc';

    const params = [userId];
    let where = 'WHERE r.user_id = $1';

    if (search && search.trim()) {
      params.push(`%${search.trim()}%`);
      where += ` AND (r.title ILIKE $${params.length} OR r.artist ILIKE $${params.length})`;
    }
    if (genre && genre.trim()) {
      params.push(genre.trim());
      where += ` AND r.genre = $${params.length}`;
    }

    const { rows } = await pool.query(
      `SELECT r.*,
         (SELECT ri.image_url
          FROM record_images ri
          WHERE ri.record_id = r.id AND ri.is_primary = TRUE
          LIMIT 1) AS primary_image_url
       FROM records r
       ${where}
       ORDER BY r.${safeSort} ${safeOrder}`,
      params
    );

    res.json({ records: rows });
  } catch (err) { next(err); }
});

// ─────────────────────────────────────────────────────────────────────────────
// POST /v1/records/lookup
// IMPORTANT: registered BEFORE /:id so "lookup" is not treated as a UUID param.
// Body: { artist?: string, title?: string }
// ─────────────────────────────────────────────────────────────────────────────
router.post('/lookup', async (req, res, next) => {
  try {
    const { artist, title } = req.body;

    if (!artist && !title) {
      return res.status(400).json({ error: 'At least one of artist or title is required' });
    }

    const result = await lookup({ artist, title });
    res.json(result);
  } catch (err) { next(err); }
});

// ─────────────────────────────────────────────────────────────────────────────
// GET /v1/records/:id
// ─────────────────────────────────────────────────────────────────────────────
router.get('/:id', async (req, res, next) => {
  try {
    const userId = await resolveUserId(req);

    const { rows } = await pool.query(
      `SELECT * FROM records WHERE id = $1 AND user_id = $2`,
      [req.params.id, userId]
    );
    if (!rows.length) return res.status(404).json({ error: 'Record not found' });

    const { rows: images } = await pool.query(
      `SELECT * FROM record_images WHERE record_id = $1 ORDER BY is_primary DESC, created_at ASC`,
      [req.params.id]
    );

    res.json({ ...rows[0], images });
  } catch (err) { next(err); }
});

// ─────────────────────────────────────────────────────────────────────────────
// POST /v1/records
// Body: { title, artist, year?, genre?, notes?, condition?, mbid? }
// ─────────────────────────────────────────────────────────────────────────────
router.post('/', async (req, res, next) => {
  try {
    const userId = await resolveUserId(req);
    const { title, artist, year, genre, notes, condition, mbid } = req.body;

    if (!title || !title.trim()) return res.status(400).json({ error: 'title is required' });
    if (!artist || !artist.trim()) return res.status(400).json({ error: 'artist is required' });

    const { rows } = await pool.query(
      `INSERT INTO records (user_id, title, artist, year, genre, notes, condition, mbid)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
       RETURNING *`,
      [
        userId,
        title.trim(),
        artist.trim(),
        year ? parseInt(year, 10) : null,
        genre  || null,
        notes  || null,
        condition || null,
        mbid   || null,
      ]
    );

    res.status(201).json(rows[0]);
  } catch (err) { next(err); }
});

// ─────────────────────────────────────────────────────────────────────────────
// PUT /v1/records/:id
// Partial update — COALESCE keeps existing value when field is omitted.
// ─────────────────────────────────────────────────────────────────────────────
router.put('/:id', async (req, res, next) => {
  try {
    const userId = await resolveUserId(req);
    const { title, artist, year, genre, notes, condition, mbid } = req.body;

    const { rows } = await pool.query(
      `UPDATE records
       SET title     = COALESCE($3, title),
           artist    = COALESCE($4, artist),
           year      = COALESCE($5, year),
           genre     = COALESCE($6, genre),
           notes     = COALESCE($7, notes),
           condition = COALESCE($8, condition),
           mbid      = COALESCE($9, mbid)
       WHERE id = $1 AND user_id = $2
       RETURNING *`,
      [
        req.params.id,
        userId,
        title  || null,
        artist || null,
        year   ? parseInt(year, 10) : null,
        genre  || null,
        notes  || null,
        condition || null,
        mbid   || null,
      ]
    );

    if (!rows.length) return res.status(404).json({ error: 'Record not found' });
    res.json(rows[0]);
  } catch (err) { next(err); }
});

// ─────────────────────────────────────────────────────────────────────────────
// DELETE /v1/records/:id
// ─────────────────────────────────────────────────────────────────────────────
router.delete('/:id', async (req, res, next) => {
  try {
    const userId = await resolveUserId(req);

    const { rowCount } = await pool.query(
      `DELETE FROM records WHERE id = $1 AND user_id = $2`,
      [req.params.id, userId]
    );

    if (!rowCount) return res.status(404).json({ error: 'Record not found' });
    res.status(204).send();
  } catch (err) { next(err); }
});

// ─────────────────────────────────────────────────────────────────────────────
// POST /v1/records/:id/images
// Multipart form: field "image" (file) + field "image_type" + optional "is_primary"
// ─────────────────────────────────────────────────────────────────────────────
router.post('/:id/images', upload.single('image'), async (req, res, next) => {
  try {
    const userId = await resolveUserId(req);

    // Verify the record belongs to this user before accepting the upload
    const { rows: owned } = await pool.query(
      `SELECT id FROM records WHERE id = $1 AND user_id = $2`,
      [req.params.id, userId]
    );
    if (!owned.length) return res.status(404).json({ error: 'Record not found' });

    if (!req.file) return res.status(400).json({ error: 'No image file provided (field name: image)' });

    const imageType = req.body.image_type || 'photo';
    const isPrimary = req.body.is_primary === 'true';

    const imageUrl = await uploadImage(req.file.buffer, req.file.originalname, userId);

    // Enforce at-most-one primary per record
    if (isPrimary) {
      await pool.query(
        `UPDATE record_images SET is_primary = FALSE WHERE record_id = $1`,
        [req.params.id]
      );
    }

    const { rows } = await pool.query(
      `INSERT INTO record_images (record_id, image_url, image_type, is_primary)
       VALUES ($1, $2, $3, $4)
       RETURNING *`,
      [req.params.id, imageUrl, imageType, isPrimary]
    );

    res.status(201).json(rows[0]);
  } catch (err) { next(err); }
});

module.exports = router;
