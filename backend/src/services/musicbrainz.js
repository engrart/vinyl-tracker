const axios = require('axios');

const MB_BASE = 'https://musicbrainz.org/ws/2';
const CAA_BASE = 'https://coverartarchive.org';

// MusicBrainz requires a descriptive User-Agent or requests will be blocked.
// https://musicbrainz.org/doc/MusicBrainz_API/Rate_Limiting
const userAgent = () =>
  `VinylTracker/1.0 (${process.env.CONTACT_EMAIL || 'admin@vinyltracker.app'})`;

const mbClient = axios.create({
  baseURL: MB_BASE,
  timeout: 10_000,
  headers: { Accept: 'application/json' },
});

const caaClient = axios.create({
  baseURL: CAA_BASE,
  timeout: 8_000,
  // CAA redirects; axios follows by default
  maxRedirects: 5,
});

/**
 * Search MusicBrainz for releases matching artist and/or title.
 * Returns up to 5 release objects from the MB JSON response.
 *
 * MB Lucene query syntax:
 *   release:"Abbey Road" AND artist:"Beatles"
 */
async function searchRelease({ artist, title }) {
  const parts = [];
  if (title)  parts.push(`release:"${title.replace(/"/g, '')}"`);
  if (artist) parts.push(`artist:"${artist.replace(/"/g, '')}"`);

  if (!parts.length) return [];

  const { data } = await mbClient.get('/release/', {
    params: {
      query: parts.join(' AND '),
      fmt: 'json',
      limit: 5,
      inc: 'artist-credits+release-groups+genres',
    },
    headers: { 'User-Agent': userAgent() },
  });

  return data.releases || [];
}

/**
 * Fetch the front cover art URL from Cover Art Archive for a given MBID.
 * Returns null if no art is available (graceful fallback).
 *
 * CAA endpoint: GET /release/{mbid}
 * Returns JSON with an `images` array; each image has `front`, `thumbnails`, `image`.
 */
async function getCoverArt(mbid) {
  try {
    const { data } = await caaClient.get(`/release/${mbid}`, {
      headers: { 'User-Agent': userAgent() },
    });

    const images = data.images || [];
    const front = images.find((img) => img.front) || images[0];
    if (!front) return null;

    // Prefer the 500px thumbnail; fall back to full image URL
    return front.thumbnails?.['500'] || front.thumbnails?.large || front.image || null;
  } catch (err) {
    // 404 from CAA simply means no art indexed yet — not an error
    if (err.response?.status === 404) return null;
    // Other errors (network, 5xx): log and continue
    console.warn(`[musicbrainz] CAA fetch failed for ${mbid}:`, err.message);
    return null;
  }
}

/**
 * Full lookup: search MB → parse top result → fetch cover art.
 * Returns a structured metadata object ready to send to the client.
 */
async function lookup({ artist, title }) {
  const releases = await searchRelease({ artist, title });

  if (!releases.length) {
    return { title: title || null, artist: artist || null, confidence: 0 };
  }

  const top = releases[0];
  const mbid = top.id;

  // Artist credit: prefer the joined string; fall back to first artist name
  const resultArtist =
    top['artist-credit']?.[0]?.artist?.name ||
    top['artist-credit']?.[0]?.name ||
    artist ||
    null;

  // Year: first-release-date can be "YYYY", "YYYY-MM", or "YYYY-MM-DD"
  const dateStr = top['first-release-date'] || top.date || '';
  const year = dateStr ? parseInt(dateStr.slice(0, 4), 10) || null : null;

  // Genre: MB exposes tags on release-group; also check top-level genres
  const genre =
    top['release-group']?.genres?.[0]?.name ||
    top.genres?.[0]?.name ||
    top['release-group']?.['primary-type'] ||
    null;

  // MusicBrainz returns a 0-100 score for text search relevance
  const confidence = (top.score ?? 0) / 100;

  const coverArtUrl = await getCoverArt(mbid);

  return {
    title: top.title,
    artist: resultArtist,
    year,
    genre,
    mbid,
    coverArtUrl,
    confidence,
  };
}

module.exports = { searchRelease, getCoverArt, lookup };
