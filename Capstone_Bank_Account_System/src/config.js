const number = (value, fallback) => Number.isFinite(Number(value)) ? Number(value) : fallback;

export const config = {
  port: number(process.env.PORT, 3000),
  databaseUrl: process.env.DATABASE_URL || 'postgres://bank_app:bank_app_pwd@localhost:15432/bankdb',
  redisUrl: process.env.REDIS_URL || 'redis://localhost:6379',
  kafkaBrokers: (process.env.KAFKA_BROKERS || 'localhost:9092').split(',').map((broker) => broker.trim()),
  kafkaClientId: process.env.KAFKA_CLIENT_ID || 'horizon-bank-api',
  dailyTransferLimit: number(process.env.DAILY_TRANSFER_LIMIT, 500000)
};