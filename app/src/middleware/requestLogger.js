const { v4: uuidv4 } = require('uuid');
const logger = require('../logger');

/**
 * Attaches a unique requestId to every request and logs
 * method, path, status, and duration on response finish.
 *
 * The requestId is returned in the X-Request-ID header so it can be
 * correlated across services and in CloudWatch Logs.
 */
function requestLogger(req, res, next) {
  req.id = req.headers['x-request-id'] || uuidv4();
  res.setHeader('X-Request-ID', req.id);

  const start = Date.now();

  res.on('finish', () => {
    const duration = Date.now() - start;
    const level = res.statusCode >= 500 ? 'error'
                : res.statusCode >= 400 ? 'warn'
                : 'info';

    logger[level]('HTTP request', {
      requestId:  req.id,
      method:     req.method,
      path:       req.path,
      statusCode: res.statusCode,
      duration_ms: duration,
      userAgent:  req.headers['user-agent'],
      ip:         req.ip,
    });
  });

  next();
}

module.exports = requestLogger;
