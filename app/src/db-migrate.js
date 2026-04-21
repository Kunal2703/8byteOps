/**
 * Simple DB migration script — run once on first deploy (or as a Kubernetes Job).
 *
 * In production this would be replaced by a proper migration tool (Flyway / Liquibase),
 * but for this demo it keeps the setup self-contained.
 */
require('dotenv').config();

const { pool } = require('./db');
const logger   = require('./logger');

async function migrate() {
  const client = await pool.connect();
  try {
    logger.info('Running DB migrations...');

    await client.query(`
      CREATE TABLE IF NOT EXISTS todos (
        id          UUID        PRIMARY KEY,
        title       VARCHAR(255) NOT NULL,
        description TEXT         NOT NULL DEFAULT '',
        completed   BOOLEAN      NOT NULL DEFAULT false,
        created_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
        updated_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW()
      );
    `);

    await client.query(`
      CREATE INDEX IF NOT EXISTS idx_todos_created_at ON todos (created_at DESC);
    `);

    logger.info('DB migrations completed successfully');
  } catch (err) {
    logger.error('DB migration failed', { error: err.message, stack: err.stack });
    process.exit(1);
  } finally {
    client.release();
    await pool.end();
  }
}

migrate();
