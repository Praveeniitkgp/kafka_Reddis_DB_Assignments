import { Kafka } from 'kafkajs';
import { config } from '../config.js';

export function createEventPublisher() {
  const producer = new Kafka({ clientId: config.kafkaClientId, brokers: config.kafkaBrokers }).producer();
  let available = false;
  return {
    async connect() {
      try { await producer.connect(); available = true; }
      catch (error) { console.warn('Kafka unavailable; continuing without events:', error.message); }
    },
    async publish(topic, key, event) {
      if (!available) return;
      try { await producer.send({ topic, messages: [{ key, value: JSON.stringify(event) }] }); }
      catch (error) { console.error('Kafka publish failed:', error.message); }
    },
    async close() { if (available) await producer.disconnect(); }
  };
}