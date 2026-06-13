const { createClient } = require('redis');

const { config } = require('./config');

let client = null;
let connectPromise = null;
let retryAfter = 0;

async function cacheGetJson(key) {
  const value = await cacheGetText(key);
  if (!value) {
    return null;
  }
  try {
    return JSON.parse(value);
  } catch (_) {
    return null;
  }
}

async function cacheGetText(key) {
  const redis = await getRedisClient();
  if (!redis) {
    return null;
  }
  try {
    return await redis.get(key);
  } catch (error) {
    markUnavailable(error);
    return null;
  }
}

async function cacheSetJson(key, value, ttlSeconds = config.redisCacheTtlSeconds) {
  const redis = await getRedisClient();
  if (!redis) {
    return false;
  }
  try {
    await redis.set(key, JSON.stringify(value), {
      EX: Math.max(1, Math.round(ttlSeconds)),
    });
    return true;
  } catch (error) {
    markUnavailable(error);
    return false;
  }
}

async function cacheIncrement(key) {
  const redis = await getRedisClient();
  if (!redis) {
    return null;
  }
  try {
    return await redis.incr(key);
  } catch (error) {
    markUnavailable(error);
    return null;
  }
}

async function cacheStatus() {
  if (!config.redisUrl) {
    return { enabled: false, connected: false };
  }
  const redis = await getRedisClient();
  return { enabled: true, connected: Boolean(redis?.isReady) };
}

async function getRedisClient() {
  if (!config.redisUrl || Date.now() < retryAfter) {
    return null;
  }
  if (!client) {
    client = createClient({
      url: config.redisUrl,
      socket: {
        connectTimeout: 5000,
        reconnectStrategy(retries) {
          return Math.min(250 * Math.max(1, retries), 5000);
        },
      },
    });
    client.on('error', (error) => {
      if (Date.now() >= retryAfter) {
        console.error('Redis cache error:', error.message);
      }
    });
  }
  if (client.isReady) {
    return client;
  }
  if (client.isOpen) {
    return null;
  }
  if (!connectPromise) {
    connectPromise = client.connect().catch((error) => {
      markUnavailable(error);
      return null;
    }).finally(() => {
      connectPromise = null;
    });
  }
  await connectPromise;
  return client.isReady ? client : null;
}

function markUnavailable(error) {
  retryAfter = Date.now() + 30000;
  console.error('Redis cache unavailable:', error.message);
}

module.exports = {
  cacheGetJson,
  cacheGetText,
  cacheIncrement,
  cacheSetJson,
  cacheStatus,
};
