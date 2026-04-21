const logger = require('../logger');

/**
 * Central error handler — must be registered last (4-arg signature).
 *
 * Catches anything passed to next(err) from route handlers.
 * Logs the full stack trace but only returns a safe message to the client.
 */
// eslint-disable-next-line no-unused-vars
function errorHandler(err, req, res, next) {
  logger.error('Unhandled error', {
    requestId: req.id,
    error:     err.message,
    stack:     err.stack,
    method:    req.method,
    path:      req.path,
  });

  // Don't leak internal error details to clients in production
  const statusCode = err.statusCode || 500;
  const message    = process.env.NODE_ENV === 'production'
    ? 'Internal server error'
    : err.message;

  res.status(statusCode).json({ error: message });
}

module.exports = errorHandler;
