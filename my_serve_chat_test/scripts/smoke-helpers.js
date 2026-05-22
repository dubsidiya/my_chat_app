/**
 * Shared helpers for backend smoke scripts.
 */
import express from 'express';
import http from 'http';
import reportsRoutes from '../routes/reports.js';
import studentsRoutes from '../routes/students.js';
import { generateToken } from '../middleware/auth.js';
import pool from '../db.js';

export const assert = (cond, msg) => {
  if (!cond) throw new Error(msg);
};

export const makeRes = () => ({
  statusCode: 200,
  body: null,
  status(code) {
    this.statusCode = code;
    return this;
  },
  json(payload) {
    this.body = payload;
    return this;
  },
  send(payload) {
    this.body = payload;
    return this;
  },
});

/** Minimal Express app with real /reports and /students routers (route middleware included). */
export const withSmokeHttpServer = async (handler) => {
  const app = express();
  app.use(express.json());
  app.use('/reports', reportsRoutes);
  app.use('/students', studentsRoutes);

  const server = http.createServer(app);
  await new Promise((resolve, reject) => {
    server.listen(0, '127.0.0.1', (err) => (err ? reject(err) : resolve()));
  });

  const addr = server.address();
  assert(addr && typeof addr === 'object' && addr.port, 'smoke HTTP server: no port');
  const base = `http://127.0.0.1:${addr.port}`;

  try {
    await handler(base);
  } finally {
    await new Promise((resolve, reject) => {
      server.close((err) => (err ? reject(err) : resolve()));
    });
  }
};

export const loadUsers = async () => {
  const usersRes = await pool.query(
    `SELECT id, email, COALESCE(token_version, 0) AS token_version
     FROM users
     ORDER BY id ASC`
  );
  return usersRes.rows.map((u) => ({
    userId: Number(u.id),
    email: (u.email || '').toString(),
    username: (u.email || '').toString(),
    tokenVersion: Number(u.token_version ?? 0),
  }));
};

export const tokenForUser = (user, privateAccessFlag) =>
  generateToken(user.userId, user.email, privateAccessFlag === true, user.tokenVersion ?? 0);

export const httpRequest = async (base, path, { token, method = 'GET', body, headers = {} } = {}) => {
  const res = await fetch(`${base}${path}`, {
    method,
    headers: {
      ...(body != null ? { 'Content-Type': 'application/json' } : {}),
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
      ...headers,
    },
    body: body != null ? JSON.stringify(body) : undefined,
  });
  let json = null;
  const text = await res.text();
  if (text) {
    try {
      json = JSON.parse(text);
    } catch (_) {
      json = text;
    }
  }
  return { status: res.status, body: json, text };
};
