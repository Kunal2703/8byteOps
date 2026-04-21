const request = require('supertest');
const app     = require('../src/index');
const db      = require('../src/db');

jest.mock('../src/db', () => ({
  ping:  jest.fn().mockResolvedValue(true),
  query: jest.fn(),
  pool:  { on: jest.fn() },
}));

const mockTodo = {
  id:          'abc-123',
  title:       'Write Terraform modules',
  description: 'VPC, EKS, RDS',
  completed:   false,
  created_at:  new Date().toISOString(),
  updated_at:  new Date().toISOString(),
};

describe('Todos endpoints', () => {
  beforeEach(() => jest.clearAllMocks());

  // ── GET /todos ─────────────────────────────────────────────────────────────
  describe('GET /todos', () => {
    it('returns 200 with list of todos', async () => {
      db.query.mockResolvedValueOnce({ rows: [mockTodo], rowCount: 1 });

      const res = await request(app).get('/todos');
      expect(res.statusCode).toBe(200);
      expect(res.body.data).toHaveLength(1);
      expect(res.body.count).toBe(1);
    });

    it('returns empty array when no todos exist', async () => {
      db.query.mockResolvedValueOnce({ rows: [], rowCount: 0 });

      const res = await request(app).get('/todos');
      expect(res.statusCode).toBe(200);
      expect(res.body.data).toHaveLength(0);
    });
  });

  // ── GET /todos/:id ─────────────────────────────────────────────────────────
  describe('GET /todos/:id', () => {
    it('returns 200 with the todo', async () => {
      db.query.mockResolvedValueOnce({ rows: [mockTodo], rowCount: 1 });

      const res = await request(app).get('/todos/abc-123');
      expect(res.statusCode).toBe(200);
      expect(res.body.data.id).toBe('abc-123');
    });

    it('returns 404 when todo does not exist', async () => {
      db.query.mockResolvedValueOnce({ rows: [], rowCount: 0 });

      const res = await request(app).get('/todos/nonexistent');
      expect(res.statusCode).toBe(404);
    });
  });

  // ── POST /todos ────────────────────────────────────────────────────────────
  describe('POST /todos', () => {
    it('creates a todo and returns 201', async () => {
      db.query.mockResolvedValueOnce({ rows: [mockTodo], rowCount: 1 });

      const res = await request(app)
        .post('/todos')
        .send({ title: 'Write Terraform modules', description: 'VPC, EKS, RDS' });

      expect(res.statusCode).toBe(201);
      expect(res.body.data.title).toBe('Write Terraform modules');
    });

    it('returns 400 when title is missing', async () => {
      const res = await request(app)
        .post('/todos')
        .send({ description: 'No title provided' });

      expect(res.statusCode).toBe(400);
      expect(res.body.errors).toBeDefined();
    });

    it('returns 400 when title is empty string', async () => {
      const res = await request(app)
        .post('/todos')
        .send({ title: '   ' });

      expect(res.statusCode).toBe(400);
    });
  });

  // ── PATCH /todos/:id ───────────────────────────────────────────────────────
  describe('PATCH /todos/:id', () => {
    it('updates a todo and returns 200', async () => {
      db.query
        .mockResolvedValueOnce({ rows: [mockTodo], rowCount: 1 })   // SELECT existing
        .mockResolvedValueOnce({ rows: [{ ...mockTodo, completed: true }], rowCount: 1 }); // UPDATE

      const res = await request(app)
        .patch('/todos/abc-123')
        .send({ completed: true });

      expect(res.statusCode).toBe(200);
      expect(res.body.data.completed).toBe(true);
    });

    it('returns 404 when todo does not exist', async () => {
      db.query.mockResolvedValueOnce({ rows: [], rowCount: 0 });

      const res = await request(app)
        .patch('/todos/nonexistent')
        .send({ completed: true });

      expect(res.statusCode).toBe(404);
    });
  });

  // ── DELETE /todos/:id ──────────────────────────────────────────────────────
  describe('DELETE /todos/:id', () => {
    it('deletes a todo and returns 200', async () => {
      db.query.mockResolvedValueOnce({ rows: [{ id: 'abc-123' }], rowCount: 1 });

      const res = await request(app).delete('/todos/abc-123');
      expect(res.statusCode).toBe(200);
      expect(res.body.id).toBe('abc-123');
    });

    it('returns 404 when todo does not exist', async () => {
      db.query.mockResolvedValueOnce({ rows: [], rowCount: 0 });

      const res = await request(app).delete('/todos/nonexistent');
      expect(res.statusCode).toBe(404);
    });
  });
});
