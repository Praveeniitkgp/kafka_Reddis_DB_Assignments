import { createClient } from 'redis';
import { config } from '../config.js';

export function createCache() {
  const client = createClient({ url: config.redisUrl });
  client.on('error', (error) => console.error('Redis error:', error.message));
  let available = false;
  return {
    async connect() {
      try { await client.connect(); available = true; }
      catch (error) { console.warn('Redis unavailable; continuing without cache:', error.message); }
    },
    async get(key) {
      if (!available) return null;
      try { return await client.get(key); } catch { return null; }
    },
    async set(key, value, seconds = 60) {
      if (!available) return;
      try { await client.set(key, value, { EX: seconds }); } catch { /* optional cache */ }
    },
    async del(...keys) {
      if (!available || keys.length === 0) return;
      try { await client.del(keys); } catch { /* optional cache */ }
    },
    async delPrefix(prefix) {
      if (!available) return;
      try {
        const keys = [];
        for await (const key of client.scanIterator({ MATCH: `${prefix}*`, COUNT: 100 })) keys.push(key);
        if (keys.length) await client.del(keys);
      } catch { /* optional cache */ }
    },
    async close() { if (available) await client.quit(); }
  };
}