const crypto = require('crypto');

const AI_JOB_STATUSES = Object.freeze({
  queued: 'queued',
  running: 'running',
  waitingForReview: 'waiting_for_review',
  completed: 'completed',
  failed: 'failed',
  cancelled: 'cancelled',
});

module.exports = {
  AI_JOB_STATUSES,
  createAiJobsModule,
};

function createAiJobsModule({ query, withTransaction, normalizeOptionalText }) {
  const streams = new Map();
  const queuedJobIds = [];
  const queuedSet = new Set();
  let schemaReady = false;
  let runnerActive = false;
  const handlers = new Map();

  async function ensureSchema(target = query) {
    await run(target, `
      CREATE TABLE IF NOT EXISTS ai_jobs (
        id TEXT PRIMARY KEY,
        business_id TEXT NOT NULL,
        branch_id TEXT,
        user_id TEXT,
        job_type TEXT NOT NULL,
        status TEXT NOT NULL,
        title TEXT,
        source_file_name TEXT,
        source_file_url TEXT,
        source_file_base64 TEXT,
        source_mime_type TEXT,
        source_extension TEXT,
        source_text TEXT,
        instruction TEXT,
        progress INTEGER NOT NULL DEFAULT 0,
        total_steps INTEGER NOT NULL DEFAULT 0,
        completed_steps INTEGER NOT NULL DEFAULT 0,
        current_step TEXT,
        result_json TEXT,
        error_message TEXT,
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        started_at TIMESTAMPTZ,
        completed_at TIMESTAMPTZ,
        cancelled_at TIMESTAMPTZ
      )
    `);
    await run(target, `
      CREATE INDEX IF NOT EXISTS idx_ai_jobs_business_status_created
      ON ai_jobs (business_id, status, created_at DESC)
    `);
    await run(target, `
      CREATE TABLE IF NOT EXISTS ai_job_events (
        id TEXT PRIMARY KEY,
        job_id TEXT NOT NULL REFERENCES ai_jobs(id) ON DELETE CASCADE,
        business_id TEXT NOT NULL,
        branch_id TEXT,
        event_type TEXT NOT NULL,
        level TEXT NOT NULL DEFAULT 'info',
        title TEXT NOT NULL,
        message TEXT,
        tool_name TEXT,
        entity_type TEXT,
        entity_id TEXT,
        entity_name TEXT,
        progress INTEGER,
        metadata_json TEXT,
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
      )
    `);
    await run(target, `
      CREATE INDEX IF NOT EXISTS idx_ai_job_events_job_created
      ON ai_job_events (job_id, created_at ASC)
    `);
    await run(target, `
      CREATE TABLE IF NOT EXISTS ai_import_draft_items (
        id TEXT PRIMARY KEY,
        job_id TEXT NOT NULL REFERENCES ai_jobs(id) ON DELETE CASCADE,
        business_id TEXT NOT NULL,
        branch_id TEXT,
        raw_text TEXT,
        product_name TEXT,
        category_name TEXT,
        barcode TEXT,
        sku TEXT,
        unit TEXT,
        cost_price NUMERIC,
        selling_price NUMERIC,
        stock_quantity NUMERIC,
        supplier_name TEXT,
        confidence NUMERIC,
        status TEXT NOT NULL DEFAULT 'needs_review',
        warnings_json TEXT,
        matched_product_id TEXT,
        row_json TEXT,
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
      )
    `);
    await run(target, `
      CREATE INDEX IF NOT EXISTS idx_ai_import_draft_items_job
      ON ai_import_draft_items (job_id, created_at ASC)
    `);
    schemaReady = true;
  }

  function registerHandler(jobType, handler) {
    handlers.set(jobType, handler);
  }

  async function createJob({
    businessId,
    branchId = null,
    userId = null,
    jobType,
    title,
    sourceFileName,
    sourceFileBase64,
    sourceMimeType = null,
    sourceExtension = null,
    sourceText = null,
    instruction = null,
    totalSteps = 6,
  }) {
    await ensureSchemaOnce();
    const jobId = crypto.randomUUID();
    const now = new Date().toISOString();
    await query(
      `
      INSERT INTO ai_jobs (
        id, business_id, branch_id, user_id, job_type, status, title,
        source_file_name, source_file_base64, source_mime_type, source_extension,
        source_text, instruction, progress, total_steps, completed_steps,
        current_step, created_at
      )
      VALUES ($1, $2, $3, $4, $5, 'queued', $6, $7, $8, $9, $10, $11, $12, 0, $13, 0, $14, $15)
      `,
      [
        jobId,
        businessId,
        branchId,
        userId,
        jobType,
        title,
        sourceFileName,
        sourceFileBase64,
        sourceMimeType,
        sourceExtension,
        sourceText,
        instruction,
        totalSteps,
        'Queued',
        now,
      ],
    );
    await addEvent({
      jobId,
      businessId,
      branchId,
      eventType: 'file_received',
      title: 'Uploaded file received',
      message: sourceFileName ? `Received ${sourceFileName}` : 'Received uploaded file',
      progress: 2,
      metadata: { sourceFileName },
    });
    enqueue(jobId);
    return getJob(jobId, businessId);
  }

  function enqueue(jobId) {
    if (!queuedSet.has(jobId)) {
      queuedSet.add(jobId);
      queuedJobIds.push(jobId);
    }
    setTimeout(runNext, 0);
  }

  async function enqueueQueuedJobs() {
    await ensureSchemaOnce();
    await query(
      `
      UPDATE ai_jobs
      SET status = 'queued',
          current_step = 'Queued after backend restart',
          progress = 0,
          started_at = NULL
      WHERE status = 'running'
      `
    );
    const result = await query(
      `
      SELECT id
      FROM ai_jobs
      WHERE status = 'queued'
      ORDER BY created_at ASC
      LIMIT 20
      `,
    );
    for (const row of result.rows) {
      enqueue(row.id);
    }
  }

  async function runNext() {
    if (runnerActive) return;
    runnerActive = true;
    try {
      while (queuedJobIds.length > 0) {
        const jobId = queuedJobIds.shift();
        queuedSet.delete(jobId);
        await runJob(jobId);
      }
    } finally {
      runnerActive = false;
    }
  }

  async function runJob(jobId) {
    await ensureSchemaOnce();
    const result = await query('SELECT * FROM ai_jobs WHERE id = $1 LIMIT 1', [jobId]);
    const job = result.rows[0];
    if (!job || job.status !== AI_JOB_STATUSES.queued) {
      return;
    }
    const handler = handlers.get(job.job_type);
    if (!handler) {
      await markFailed(job, `No AI job handler is registered for ${job.job_type}`);
      return;
    }

    try {
      await updateJob(job.id, job.business_id, {
        status: AI_JOB_STATUSES.running,
        startedAt: new Date().toISOString(),
        currentStep: 'Starting Piki worker',
        progress: 5,
      });
      await addEvent({
        jobId: job.id,
        businessId: job.business_id,
        branchId: job.branch_id,
        eventType: 'job_started',
        title: 'Piki started working',
        message: job.title || 'Preparing AI import',
        progress: 5,
      });
      await handler({
        job,
        updateJob,
        addEvent,
        saveDraftItems,
        getJob,
      });
    } catch (error) {
      await markFailed(job, error?.message || 'AI job failed');
    }
  }

  async function markFailed(job, message) {
    await updateJob(job.id, job.business_id, {
      status: AI_JOB_STATUSES.failed,
      errorMessage: message,
      currentStep: 'Failed',
      completedAt: new Date().toISOString(),
    });
    await addEvent({
      jobId: job.id,
      businessId: job.business_id,
      branchId: job.branch_id,
      eventType: 'error',
      level: 'error',
      title: 'Piki job failed',
      message,
      progress: null,
    });
  }

  async function updateJob(jobId, businessId, changes) {
    const assignments = [];
    const values = [jobId, businessId];
    const set = (column, value) => {
      values.push(value);
      assignments.push(`${column} = $${values.length}`);
    };

    if (changes.status != null) set('status', changes.status);
    if (changes.progress != null) set('progress', clampProgress(changes.progress));
    if (changes.totalSteps != null) set('total_steps', Number(changes.totalSteps) || 0);
    if (changes.completedSteps != null) set('completed_steps', Number(changes.completedSteps) || 0);
    if (changes.currentStep != null) set('current_step', limitText(changes.currentStep, 240));
    if (changes.resultJson !== undefined) set('result_json', stringifyJson(changes.resultJson));
    if (changes.errorMessage !== undefined) set('error_message', changes.errorMessage);
    if (changes.startedAt !== undefined) set('started_at', changes.startedAt);
    if (changes.completedAt !== undefined) set('completed_at', changes.completedAt);
    if (changes.cancelledAt !== undefined) set('cancelled_at', changes.cancelledAt);

    if (assignments.length === 0) {
      return null;
    }

    const result = await query(
      `
      UPDATE ai_jobs
      SET ${assignments.join(', ')}
      WHERE id = $1 AND business_id = $2
      RETURNING *
      `,
      values,
    );
    const row = result.rows[0] || null;
    if (row) {
      publish(jobId, { type: 'job', job: serializeJob(row) });
    }
    return row;
  }

  async function addEvent({
    jobId,
    businessId,
    branchId = null,
    eventType,
    level = 'info',
    title,
    message = null,
    toolName = null,
    entityType = null,
    entityId = null,
    entityName = null,
    progress = null,
    metadata = null,
  }) {
    await ensureSchemaOnce();
    const eventId = crypto.randomUUID();
    const result = await query(
      `
      INSERT INTO ai_job_events (
        id, job_id, business_id, branch_id, event_type, level, title, message,
        tool_name, entity_type, entity_id, entity_name, progress, metadata_json
      )
      VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14)
      RETURNING *
      `,
      [
        eventId,
        jobId,
        businessId,
        branchId,
        eventType,
        level,
        limitText(title, 180),
        message == null ? null : limitText(message, 500),
        toolName,
        entityType,
        entityId,
        entityName == null ? null : limitText(entityName, 240),
        progress == null ? null : clampProgress(progress),
        stringifyJson(metadata),
      ],
    );
    const event = serializeEvent(result.rows[0]);
    publish(jobId, { type: 'event', event });
    return event;
  }

  async function saveDraftItems({ job, headers, rows, warnings = [] }) {
    await ensureSchemaOnce();
    await query('DELETE FROM ai_import_draft_items WHERE job_id = $1 AND business_id = $2', [
      job.id,
      job.business_id,
    ]);

    const saved = [];
    const safeHeaders = Array.isArray(headers) ? headers : [];
    for (let index = 0; index < rows.length; index += 1) {
      const cells = Array.isArray(rows[index]) ? rows[index] : [];
      const row = {};
      safeHeaders.forEach((header, columnIndex) => {
        row[String(header || '').trim()] = cells[columnIndex] == null ? '' : String(cells[columnIndex]).trim();
      });
      const productName = firstText(row, ['name', 'product_name', 'item', 'item_name']);
      const price = parseNumber(firstText(row, ['price', 'selling_price', 'sale_price']));
      const cost = parseNumber(firstText(row, ['cost', 'unit_cost', 'buying_price']));
      const stock = parseNumber(firstText(row, ['stock', 'stock_received', 'opening_stock', 'quantity']));
      const rowWarnings = validateDraftRow(row, { productName, price, cost });
      const status = rowWarnings.some((item) => item.level === 'error')
        ? 'invalid'
        : rowWarnings.length > 0
          ? 'needs_review'
          : 'ready';
      const draftWarnings = [
        ...warnings.slice(0, 2).map((message) => ({ level: 'info', message })),
        ...rowWarnings,
      ];
      const id = crypto.randomUUID();
      const result = await query(
        `
        INSERT INTO ai_import_draft_items (
          id, job_id, business_id, branch_id, raw_text, product_name,
          category_name, barcode, sku, unit, cost_price, selling_price,
          stock_quantity, supplier_name, confidence, status, warnings_json,
          matched_product_id, row_json
        )
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17, $18, $19)
        RETURNING *
        `,
        [
          id,
          job.id,
          job.business_id,
          job.branch_id,
          JSON.stringify(row),
          productName,
          firstText(row, ['category', 'category_name']),
          firstText(row, ['barcode', 'product_barcode', 'item_barcode']),
          firstText(row, ['sku', 'product_sku', 'item_sku']),
          firstText(row, ['unit', 'stock_unit']),
          cost,
          price,
          stock,
          firstText(row, ['supplier', 'supplier_name']),
          status === 'ready' ? 0.86 : 0.58,
          status,
          stringifyJson(draftWarnings),
          null,
          stringifyJson(row),
        ],
      );
      saved.push(serializeDraftItem(result.rows[0]));
    }
    return saved;
  }

  async function listJobs(businessId, { statuses = null, limit = 20 } = {}) {
    await ensureSchemaOnce();
    const params = [businessId, Math.min(Math.max(Number(limit) || 20, 1), 50)];
    let statusClause = '';
    if (statuses?.length) {
      params.push(statuses);
      statusClause = ` AND status = ANY($${params.length}::text[])`;
    }
    const result = await query(
      `
      SELECT *
      FROM ai_jobs
      WHERE business_id = $1${statusClause}
      ORDER BY created_at DESC
      LIMIT $2
      `,
      params,
    );
    return result.rows.map(serializeJob);
  }

  async function getJob(jobId, businessId) {
    await ensureSchemaOnce();
    const result = await query(
      'SELECT * FROM ai_jobs WHERE id = $1 AND business_id = $2 LIMIT 1',
      [jobId, businessId],
    );
    return result.rows[0] ? serializeJob(result.rows[0]) : null;
  }

  async function getEvents(jobId, businessId, { after = null, limit = 200 } = {}) {
    await ensureSchemaOnce();
    const params = [jobId, businessId, Math.min(Math.max(Number(limit) || 200, 1), 500)];
    let afterClause = '';
    if (after) {
      params.push(after);
      afterClause = ` AND created_at > (SELECT created_at FROM ai_job_events WHERE id = $${params.length} LIMIT 1)`;
    }
    const result = await query(
      `
      SELECT *
      FROM ai_job_events
      WHERE job_id = $1 AND business_id = $2${afterClause}
      ORDER BY created_at ASC
      LIMIT $3
      `,
      params,
    );
    return result.rows.map(serializeEvent);
  }

  async function getDraftItems(jobId, businessId) {
    await ensureSchemaOnce();
    const result = await query(
      `
      SELECT *
      FROM ai_import_draft_items
      WHERE job_id = $1 AND business_id = $2
      ORDER BY created_at ASC
      `,
      [jobId, businessId],
    );
    return result.rows.map(serializeDraftItem);
  }

  async function cancelJob(jobId, businessId) {
    const job = await updateJob(jobId, businessId, {
      status: AI_JOB_STATUSES.cancelled,
      cancelledAt: new Date().toISOString(),
      currentStep: 'Cancelled',
      progress: 100,
    });
    if (job) {
      await addEvent({
        jobId,
        businessId,
        branchId: job.branch_id,
        eventType: 'cancelled',
        level: 'warning',
        title: 'Piki task cancelled',
        message: 'The import job was cancelled.',
        progress: 100,
      });
    }
    return job ? serializeJob(job) : null;
  }

  async function completeJob(jobId, businessId, result = {}) {
    const existing = await getJob(jobId, businessId);
    if (!existing) return null;
    const mergedResult = {
      ...(existing.result || {}),
      importResult: result,
    };
    const row = await updateJob(jobId, businessId, {
      status: AI_JOB_STATUSES.completed,
      progress: 100,
      currentStep: 'Import completed',
      completedAt: new Date().toISOString(),
      resultJson: mergedResult,
    });
    if (row) {
      await addEvent({
        jobId,
        businessId,
        branchId: row.branch_id,
        eventType: 'completed',
        title: 'Import completed',
        message: 'Piki import actions were confirmed and completed.',
        progress: 100,
        metadata: result,
      });
    }
    return row ? serializeJob(row) : null;
  }
  async function retryJob(jobId, businessId) {
    await ensureSchemaOnce();
    const result = await query(
      `
      UPDATE ai_jobs
      SET status = 'queued',
          progress = 0,
          completed_steps = 0,
          current_step = 'Queued',
          error_message = NULL,
          started_at = NULL,
          completed_at = NULL,
          cancelled_at = NULL
      WHERE id = $1 AND business_id = $2 AND status IN ('failed', 'cancelled')
      RETURNING *
      `,
      [jobId, businessId],
    );
    const row = result.rows[0] || null;
    if (row) {
      await addEvent({
        jobId,
        businessId,
        branchId: row.branch_id,
        eventType: 'job_started',
        title: 'Piki task queued again',
        message: 'Retrying the import job.',
        progress: 1,
      });
      enqueue(jobId);
      publish(jobId, { type: 'job', job: serializeJob(row) });
    }
    return row ? serializeJob(row) : null;
  }

  function stream(jobId, res) {
    const listeners = streams.get(jobId) || new Set();
    listeners.add(res);
    streams.set(jobId, listeners);
    res.on('close', () => {
      listeners.delete(res);
      if (listeners.size === 0) {
        streams.delete(jobId);
      }
    });
  }

  function publish(jobId, payload) {
    const listeners = streams.get(jobId);
    if (!listeners || listeners.size === 0) {
      return;
    }
    const eventName = payload.type || 'message';
    const data = `event: ${eventName}\ndata: ${JSON.stringify(payload)}\n\n`;
    for (const res of listeners) {
      res.write(data);
    }
  }

  async function ensureSchemaOnce() {
    if (!schemaReady) {
      await ensureSchema();
    }
  }

  function serializeJob(row) {
    return {
      id: row.id,
      businessId: row.business_id,
      branchId: row.branch_id,
      userId: row.user_id,
      jobType: row.job_type,
      status: row.status,
      title: row.title,
      sourceFileName: row.source_file_name,
      sourceFileUrl: row.source_file_url,
      progress: Number(row.progress || 0),
      totalSteps: Number(row.total_steps || 0),
      completedSteps: Number(row.completed_steps || 0),
      currentStep: row.current_step,
      result: parseJson(row.result_json),
      errorMessage: row.error_message,
      createdAt: toIso(row.created_at),
      startedAt: toIso(row.started_at),
      completedAt: toIso(row.completed_at),
      cancelledAt: toIso(row.cancelled_at),
    };
  }

  function serializeEvent(row) {
    return {
      id: row.id,
      jobId: row.job_id,
      businessId: row.business_id,
      branchId: row.branch_id,
      eventType: row.event_type,
      level: row.level,
      title: row.title,
      message: row.message,
      toolName: row.tool_name,
      entityType: row.entity_type,
      entityId: row.entity_id,
      entityName: row.entity_name,
      progress: row.progress == null ? null : Number(row.progress),
      metadata: parseJson(row.metadata_json),
      createdAt: toIso(row.created_at),
    };
  }

  function serializeDraftItem(row) {
    return {
      id: row.id,
      jobId: row.job_id,
      productName: row.product_name,
      categoryName: row.category_name,
      barcode: row.barcode,
      sku: row.sku,
      unit: row.unit,
      costPrice: row.cost_price == null ? null : Number(row.cost_price),
      sellingPrice: row.selling_price == null ? null : Number(row.selling_price),
      stockQuantity: row.stock_quantity == null ? null : Number(row.stock_quantity),
      supplierName: row.supplier_name,
      confidence: row.confidence == null ? null : Number(row.confidence),
      status: row.status,
      warnings: parseJson(row.warnings_json) || [],
      matchedProductId: row.matched_product_id,
      row: parseJson(row.row_json) || {},
      createdAt: toIso(row.created_at),
      updatedAt: toIso(row.updated_at),
    };
  }

  return {
    ensureSchema,
    registerHandler,
    createJob,
    enqueueQueuedJobs,
    listJobs,
    getJob,
    getEvents,
    getDraftItems,
    cancelJob,
    completeJob,
    retryJob,
    stream,
  };

  async function run(target, sql, params = []) {
    if (typeof target === 'function') {
      return target(sql, params);
    }
    return target.query(sql, params);
  }

  function firstText(row, keys) {
    for (const key of keys) {
      const value = normalizeOptionalText(row[key]);
      if (value) return value;
    }
    return null;
  }
}

function validateDraftRow(row, { productName, price, cost }) {
  const warnings = [];
  if (!productName) {
    warnings.push({ level: 'error', message: 'Product name is missing.' });
  }
  if (cost != null && price != null && cost > price) {
    warnings.push({ level: 'warning', message: 'Cost is higher than selling price.' });
  }
  if (price != null && price < 0) {
    warnings.push({ level: 'error', message: 'Selling price cannot be negative.' });
  }
  if (normalizeText(row.barcode) && normalizeText(row.barcode).length < 4) {
    warnings.push({ level: 'warning', message: 'Barcode looks unusually short.' });
  }
  return warnings;
}

function normalizeText(value) {
  if (value == null) return null;
  const normalized = String(value).trim();
  return normalized === '' ? null : normalized;
}

function parseNumber(value) {
  if (value == null) return null;
  const cleaned = String(value).replace(/[, ]/g, '').trim();
  if (!cleaned) return null;
  const parsed = Number(cleaned);
  return Number.isFinite(parsed) ? parsed : null;
}

function parseJson(value) {
  if (!value) return null;
  try {
    return JSON.parse(value);
  } catch (_) {
    return null;
  }
}

function stringifyJson(value) {
  if (value == null) return null;
  try {
    return JSON.stringify(value);
  } catch (_) {
    return null;
  }
}

function clampProgress(value) {
  const number = Number(value);
  if (!Number.isFinite(number)) return 0;
  return Math.max(0, Math.min(100, Math.round(number)));
}

function limitText(value, max) {
  const text = String(value || '').trim();
  if (text.length <= max) return text;
  return text.slice(0, max - 1).trimEnd();
}

function toIso(value) {
  if (!value) return null;
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? null : date.toISOString();
}
