const express = require('express');
const { v4: uuidv4 } = require('uuid');
const { query } = require('../db');
const logger = require('../logger');

const router = express.Router();

function validateTodo(body) {
  const errors = [];
  if (!body.title || typeof body.title !== 'string' || body.title.trim() === '') {
    errors.push('title is required and must be a non-empty string');
  }
  if (body.title && body.title.length > 255) {
    errors.push('title must be 255 characters or fewer');
  }
  return errors;
}

router.get('/', async (req, res, next) => {
  try {
    const result = await query('SELECT * FROM todos ORDER BY created_at DESC', []);
    logger.info('Fetched todos', { count: result.rows.length, requestId: req.id });
    res.status(200).json({ data: result.rows, count: result.rows.length });
  } catch (err) {
    next(err);
  }
});

router.get('/:id', async (req, res, next) => {
  try {
    const result = await query('SELECT * FROM todos WHERE id = $1', [req.params.id]);
    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'Todo not found' });
    }
    res.status(200).json({ data: result.rows[0] });
  } catch (err) {
    next(err);
  }
});

router.post('/', async (req, res, next) => {
  const errors = validateTodo(req.body);
  if (errors.length > 0) {
    return res.status(400).json({ errors });
  }

  try {
    const id = uuidv4();
    const { title, description = '' } = req.body;
    const result = await query(
      `INSERT INTO todos (id, title, description, completed, created_at, updated_at)
       VALUES ($1, $2, $3, false, NOW(), NOW())
       RETURNING *`,
      [id, title.trim(), description.trim()]
    );
    logger.info('Todo created', { id, requestId: req.id });
    res.status(201).json({ data: result.rows[0] });
  } catch (err) {
    next(err);
  }
});

router.patch('/:id', async (req, res, next) => {
  try {
    const existing = await query('SELECT * FROM todos WHERE id = $1', [req.params.id]);
    if (existing.rows.length === 0) {
      return res.status(404).json({ error: 'Todo not found' });
    }

    const { title, description, completed } = req.body;
    const current = existing.rows[0];

    const updatedTitle = title !== undefined ? title.trim() : current.title;
    const updatedDescription = description !== undefined ? description.trim() : current.description;
    const updatedCompleted = completed !== undefined ? completed : current.completed;

    const result = await query(
      `UPDATE todos
       SET title = $1, description = $2, completed = $3, updated_at = NOW()
       WHERE id = $4
       RETURNING *`,
      [updatedTitle, updatedDescription, updatedCompleted, req.params.id]
    );
    logger.info('Todo updated', { id: req.params.id, requestId: req.id });
    res.status(200).json({ data: result.rows[0] });
  } catch (err) {
    next(err);
  }
});

router.delete('/:id', async (req, res, next) => {
  try {
    const result = await query('DELETE FROM todos WHERE id = $1 RETURNING id', [req.params.id]);
    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'Todo not found' });
    }
    logger.info('Todo deleted', { id: req.params.id, requestId: req.id });
    res.status(200).json({ message: 'Todo deleted', id: req.params.id });
  } catch (err) {
    next(err);
  }
});

module.exports = router;
