const { expressjwt } = require('express-jwt');
const jwksRsa = require('jwks-rsa');

// Supports both Clerk and Auth0 — configure via env vars.
//
// Clerk setup:
//   JWKS_URI  = https://<your-frontend-api>.clerk.accounts.dev/.well-known/jwks.json
//   JWT_ISSUER = https://<your-frontend-api>.clerk.accounts.dev
//   JWT_AUDIENCE = (leave blank — Clerk doesn't set aud by default)
//
// Auth0 setup:
//   JWKS_URI   = https://<domain>.auth0.com/.well-known/jwks.json
//   JWT_ISSUER  = https://<domain>.auth0.com/
//   JWT_AUDIENCE = https://your-api-identifier

if (!process.env.JWKS_URI) {
  throw new Error('JWKS_URI env var is required');
}
if (!process.env.JWT_ISSUER) {
  throw new Error('JWT_ISSUER env var is required');
}

const options = {
  secret: jwksRsa.expressJwtSecret({
    cache: true,
    rateLimit: true,
    jwksRequestsPerMinute: 10,
    jwksUri: process.env.JWKS_URI,
  }),
  issuer: process.env.JWT_ISSUER,
  algorithms: ['RS256'],
};

if (process.env.JWT_AUDIENCE) {
  options.audience = process.env.JWT_AUDIENCE;
}

// After this middleware runs, req.auth contains the decoded JWT payload.
// req.auth.sub is the Clerk user ID (e.g. "user_2abc...") or Auth0 sub.
module.exports = expressjwt(options);
