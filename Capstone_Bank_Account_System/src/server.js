import pg from 'pg';
import { config } from './config.js';
import { createApp } from './app.js';
import { createCache } from './services/cache.js';
import { createEventPublisher } from './services/events.js';
import { createBankService } from './services/bank-service.js';

const pool = new pg.Pool({ connectionString: config.databaseUrl, max: 10 });
const cache = createCache();
const events = createEventPublisher();
await Promise.all([cache.connect(), events.connect()]);
const service = createBankService(pool, cache, events, config.dailyTransferLimit);
const server = createApp(service).listen(config.port, () => console.log(`Horizon Bank API listening on http://localhost:${config.port}`));

async function shutdown() {
  server.close();
  await Promise.all([pool.end(), cache.close(), events.close()]);
}

process.once('SIGINT', shutdown);
process.once('SIGTERM', shutdown);