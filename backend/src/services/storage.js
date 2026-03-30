const { S3Client, PutObjectCommand, DeleteObjectCommand } = require('@aws-sdk/client-s3');
const { v4: uuidv4 } = require('uuid');
const path = require('path');

// Works for both Cloudflare R2 and AWS S3.
// R2: set S3_ENDPOINT to https://<account_id>.r2.cloudflarestorage.com and S3_REGION to "auto"
// S3: leave S3_ENDPOINT blank; set S3_REGION to your bucket region
const s3 = new S3Client({
  region: process.env.S3_REGION || 'auto',
  ...(process.env.S3_ENDPOINT ? { endpoint: process.env.S3_ENDPOINT } : {}),
  credentials: {
    accessKeyId: process.env.S3_ACCESS_KEY_ID,
    secretAccessKey: process.env.S3_SECRET_ACCESS_KEY,
  },
  // R2 requires path-style URLs
  forcePathStyle: !!process.env.S3_ENDPOINT,
});

const BUCKET = process.env.S3_BUCKET_NAME;
const PUBLIC_URL_BASE = (process.env.S3_PUBLIC_URL_BASE || '').replace(/\/$/, '');

const CONTENT_TYPES = {
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.png': 'image/png',
  '.webp': 'image/webp',
  '.heic': 'image/heic',
};

/**
 * Upload an image buffer to S3/R2.
 * @param {Buffer} buffer       Raw file bytes
 * @param {string} originalName Original filename (used only for extension)
 * @param {string} userId       Used to namespace the key path
 * @returns {string}            Public URL of the uploaded file
 */
async function uploadImage(buffer, originalName, userId) {
  const ext = (path.extname(originalName) || '.jpg').toLowerCase();
  const key = `users/${userId}/records/${uuidv4()}${ext}`;

  await s3.send(new PutObjectCommand({
    Bucket: BUCKET,
    Key: key,
    Body: buffer,
    ContentType: CONTENT_TYPES[ext] || 'application/octet-stream',
    CacheControl: 'public, max-age=31536000, immutable',
  }));

  return `${PUBLIC_URL_BASE}/${key}`;
}

/**
 * Delete an image from S3/R2 by its public URL.
 */
async function deleteImage(imageUrl) {
  const key = imageUrl.replace(`${PUBLIC_URL_BASE}/`, '');
  await s3.send(new DeleteObjectCommand({ Bucket: BUCKET, Key: key }));
}

module.exports = { uploadImage, deleteImage };
