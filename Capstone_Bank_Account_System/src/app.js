import express from 'express';

const required = (value) => typeof value === 'string' && value.trim().length > 0;
const datePattern = /^\d{4}-\d{2}-\d{2}$/;
const panPattern = /^[A-Z]{5}\d{4}[A-Z]$/;
const phonePattern = /^[6-9]\d{9}$/;

function validateAccount(body) {
  const errors = [];
  for (const field of ['fullName', 'email', 'phone', 'dateOfBirth', 'pan', 'accountType']) if (!required(body[field])) errors.push(`${field} is required`);
  if (body.email && body.email !== body.email.toLowerCase()) errors.push('email must be lowercase');
  if (body.phone && !phonePattern.test(body.phone)) errors.push('phone must be a valid 10-digit Indian number');
  if (body.dateOfBirth && !datePattern.test(body.dateOfBirth)) errors.push('dateOfBirth must be YYYY-MM-DD');
  if (body.pan && !panPattern.test(body.pan)) errors.push('pan must match AAAAA9999A');
  if (!['SAVINGS', 'CURRENT'].includes(body.accountType)) errors.push('accountType must be SAVINGS or CURRENT');
  if (!Number.isFinite(Number(body.initialDeposit)) || Number(body.initialDeposit) <= 0) errors.push('initialDeposit must be greater than zero');
  return errors;
}

function validateTransfer(body) {
  const errors = [];
  for (const field of ['fromAccountNumber', 'toAccountNumber', 'idempotencyKey']) if (!required(body[field])) errors.push(`${field} is required`);
  if (required(body.fromAccountNumber) && required(body.toAccountNumber) && body.fromAccountNumber === body.toAccountNumber) errors.push('source and destination accounts must differ');
  if (!Number.isFinite(Number(body.amount)) || Number(body.amount) <= 0) errors.push('amount must be greater than zero');
  if (body.idempotencyKey && body.idempotencyKey.length > 64) errors.push('idempotencyKey must be at most 64 characters');
  return errors;
}

export function createApp(service) {
  const app = express();
  app.use(express.json());
  app.get('/health', (_request, response) => response.json({ status: 'ok' }));
  app.post('/api/accounts', async (request, response, next) => {
    const errors = validateAccount(request.body);
    if (errors.length) return response.status(400).json({ error: 'Validation failed', details: errors });
    try { return response.status(201).json(await service.openAccount({ ...request.body, initialDeposit: Number(request.body.initialDeposit) })); } catch (error) { return next(error); }
  });
  app.post('/api/transfers', async (request, response, next) => {
    const errors = validateTransfer(request.body);
    if (errors.length) return response.status(400).json({ error: 'Validation failed', details: errors });
    try {
      const result = await service.transfer({ ...request.body, amount: Number(request.body.amount) });
      return response.status(result.replayed ? 200 : 201).json(result);
    } catch (error) { return next(error); }
  });
  app.get('/api/accounts/:accountNumber/statement', async (request, response, next) => {
    const { fromDate, toDate, page = '0', size = '20' } = request.query;
    const pageNumber = Number(page), pageSize = Number(size);
    if (!datePattern.test(fromDate || '') || !datePattern.test(toDate || '') || !Number.isInteger(pageNumber) || pageNumber < 0 || !Number.isInteger(pageSize) || pageSize < 1 || pageSize > 100) return response.status(400).json({ error: 'fromDate and toDate must be YYYY-MM-DD; page >= 0; size between 1 and 100' });
    try { return response.json(await service.statement(request.params.accountNumber, fromDate, toDate, pageNumber, pageSize)); } catch (error) { return next(error); }
  });
  app.use((error, _request, response, _next) => {
    if (error.code === '23505') return response.status(409).json({ error: 'A record with the same unique value already exists' });
    return response.status(error.status || 500).json({ error: error.status ? error.message : 'Internal server error' });
  });
  return app;
}