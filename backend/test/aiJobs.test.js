const test = require('node:test');
const assert = require('node:assert/strict');

const { createAiJobsModule } = require('../src/aiJobs');

test('AI jobs persist generic task payloads and support job-type recovery', async () => {
  const calls = [];
  const query = async (sql, params = []) => {
    calls.push({ sql: String(sql), params });
    return { rows: [] };
  };
  const jobs = createAiJobsModule({
    query,
    withTransaction: async (action) => action({ query }),
    normalizeOptionalText: (value) => {
      const text = value == null ? '' : String(value).trim();
      return text || null;
    },
  });

  await jobs.ensureSchema();
  await jobs.listJobs('business-1', {
    statuses: ['queued', 'running', 'completed'],
    jobTypes: ['storefront_theme'],
    limit: 20,
  });

  const schemaSql = calls.map((call) => call.sql).join('\n');
  assert.match(schemaSql, /payload_json TEXT/i);
  assert.match(schemaSql, /ADD COLUMN IF NOT EXISTS payload_json TEXT/i);

  const listCall = calls.find((call) => /SELECT \*\s+FROM ai_jobs/i.test(call.sql));
  assert.ok(listCall);
  assert.match(listCall.sql, /status = ANY\(\$3::text\[\]\)/i);
  assert.match(listCall.sql, /job_type = ANY\(\$4::text\[\]\)/i);
  assert.deepEqual(listCall.params, [
    'business-1',
    20,
    ['queued', 'running', 'completed'],
    ['storefront_theme'],
  ]);
});
