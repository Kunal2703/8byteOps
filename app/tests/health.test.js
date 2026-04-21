const request = require('supertest');
const app     = require('../src/index');

// Mock the DB ping so health tests don't need a real database
jest.mock('../src/db', () => ({
  ping:  jest.fn().mockResolvedValue(true),
  query: jest.fn(),
  pool:  { on: jest.fn() },
}));

describe('Health endpoints', () => {
  describe('GET /health', () => {
    it('returns 200 with status ok', async () => {
      const res = await request(app).get('/health');
      expect(res.statusCode).toBe(200);
      expect(res.body.status).toBe('ok');
      expect(res.body).toHaveProperty('uptime_seconds');
      expect(res.body).toHaveProperty('timestamp');
    });
  });

  describe('GET /ready', () => {
    it('returns 200 when DB is reachable', async () => {
      const res = await request(app).get('/ready');
      expect(res.statusCode).toBe(200);
      expect(res.body.status).toBe('ready');
      expect(res.body.database).toBe('connected');
    });

    it('returns 503 when DB is unreachable', async () => {
      const { ping } = require('../src/db');
      ping.mockRejectedValueOnce(new Error('Connection refused'));

      const res = await request(app).get('/ready');
      expect(res.statusCode).toBe(503);
      expect(res.body.status).toBe('not ready');
      expect(res.body.database).toBe('unreachable');
    });
  });

  describe('GET /info', () => {
    it('returns 200 with app metadata', async () => {
      const res = await request(app).get('/info');
      expect(res.statusCode).toBe(200);
      expect(res.body).toHaveProperty('app');
      expect(res.body).toHaveProperty('version');
      expect(res.body).toHaveProperty('environment');
      expect(res.body).toHaveProperty('node_version');
    });
  });
});
