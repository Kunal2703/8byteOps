const express = require('express');
const { ping } = require('../db');
const logger = require('../logger');

const router = express.Router();

router.get('/health', (_req, res) => {
  res.status(200).json({
    status: 'ok',
    uptime_seconds: Math.floor(process.uptime()),
    timestamp: new Date().toISOString(),
  });
});

router.get('/ready', async (_req, res) => {
  try {
    await ping();
    res.status(200).json({
      status: 'ready',
      database: 'connected',
      timestamp: new Date().toISOString(),
    });
  } catch (err) {
    logger.error('Readiness check failed', { error: err.message });
    res.status(503).json({
      status: 'not ready',
      database: 'unreachable',
      error: err.message,
      timestamp: new Date().toISOString(),
    });
  }
});

router.get('/info', (_req, res) => {
  res.status(200).json({
    app: 'devops-demo-app',
    version: process.env.APP_VERSION || '1.0.0',
    environment: process.env.NODE_ENV || 'development',
    node_version: process.version,
    image_tag: process.env.IMAGE_TAG || 'local',
    timestamp: new Date().toISOString(),
  });
});

module.exports = router;
