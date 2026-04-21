require('dotenv').config();

const path = require('path');
const express = require('express');
const helmet = require('helmet');
const cors = require('cors');
const promMiddleware = require('express-prometheus-middleware');

const logger = require('./logger');
const requestLogger = require('./middleware/requestLogger');
const errorHandler = require('./middleware/errorHandler');
const healthRoutes = require('./routes/health');
const todoRoutes = require('./routes/todos');

const app = express();
const PORT = parseInt(process.env.PORT || '3000', 10);

// relax CSP so inline scripts in index.html work
app.use(helmet({
  contentSecurityPolicy: false,
}));

app.use(cors({
  origin: process.env.ALLOWED_ORIGINS ? process.env.ALLOWED_ORIGINS.split(',') : '*',
}));

app.use(express.json({ limit: '10kb' }));

app.use(requestLogger);

app.use(promMiddleware({
  metricsPath: '/metrics',
  collectDefaultMetrics: true,
  requestDurationBuckets: [0.1, 0.5, 1, 1.5, 2, 3, 5, 10],
  requestLengthBuckets: [512, 1024, 5120, 10240],
  responseLengthBuckets: [512, 1024, 5120, 10240],
}));

app.use(express.static(path.join(__dirname, '..', 'public')));

app.use('/', healthRoutes);
app.use('/todos', todoRoutes);

app.use((_req, res) => {
  res.status(404).json({ error: 'Route not found' });
});

app.use(errorHandler);

if (require.main === module) {
  app.listen(PORT, () => {
    logger.info('Server started', {
      port: PORT,
      environment: process.env.NODE_ENV || 'development',
      version: process.env.APP_VERSION || '1.0.0',
    });
  });

  process.on('SIGTERM', () => {
    logger.info('SIGTERM received, shutting down');
    process.exit(0);
  });

  process.on('SIGINT', () => {
    logger.info('SIGINT received, shutting down');
    process.exit(0);
  });
}

module.exports = app;
