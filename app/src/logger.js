const winston = require('winston');

// Structured JSON logging — required for CloudWatch Logs Insights queries
const logger = winston.createLogger({
  level: process.env.LOG_LEVEL || 'info',
  format: winston.format.combine(
    winston.format.timestamp(),
    winston.format.errors({ stack: true }),
    winston.format.json()           // CloudWatch Insights parses JSON natively
  ),
  defaultMeta: {
    service: 'devops-demo-app',
    environment: process.env.NODE_ENV || 'development',
    version: process.env.APP_VERSION || '1.0.0',
  },
  transports: [
    new winston.transports.Console(),
  ],
});

module.exports = logger;
