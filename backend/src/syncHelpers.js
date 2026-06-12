const { getTableConfig } = require('./syncTables');

const SERVER_SYNC_STATUS = 'synced';

const NULLABLE_TIMESTAMP_COLUMNS = new Set([
  'deleted_at',
  'closed_at',
  'finished_at',
  'refunded_at',
]);

const NULLABLE_TIMESTAMP_FIELDS = new Set([
  'customer_invoices.sent_at',
  'customer_invoices.paid_at',
  'sales.etims_submitted_at',
  'service_orders.scheduled_at',
  'service_orders.checked_in_at',
  'stock_transfers.approved_at',
  'stock_transfers.received_at',
]);

function prepareIncomingRecord(tableName, record) {
  const config = getTableConfig(tableName);
  const rawRecord =
    record && typeof record === 'object' && !Array.isArray(record) ? record : {};
  const prepared = {};

  for (const column of config.columns) {
    if (column === 'sync_status') {
      continue;
    }
    if (Object.prototype.hasOwnProperty.call(rawRecord, column)) {
      prepared[column] = rawRecord[column];
    }
  }

  const id = normalizeId(prepared.id);
  if (!id) {
    return invalidResult('missing_id', 'Record id is required', {
      field: 'id',
    });
  }
  prepared.id = id;

  const updatedAt = normalizeTimestampField(prepared.updated_at, {
    field: 'updated_at',
    required: true,
  });
  if (!updatedAt.ok) {
    return updatedAt;
  }
  prepared.updated_at = updatedAt.value;

  const createdAt = normalizeTimestampField(prepared.created_at, {
    field: 'created_at',
    required: false,
    fallback: prepared.updated_at,
  });
  if (!createdAt.ok) {
    return createdAt;
  }
  prepared.created_at = createdAt.value;

  for (const column of config.columns) {
    if (!column.endsWith('_at') || column === 'sync_status') {
      continue;
    }
    if (column === 'created_at' || column === 'updated_at') {
      continue;
    }

    const hadTimestampField = Object.prototype.hasOwnProperty.call(
      prepared,
      column,
    );
    const nullableTimestamp = isNullableTimestampField(tableName, column);
    const normalized = normalizeTimestampField(prepared[column], {
      field: column,
      required: !nullableTimestamp,
      fallback: nullableTimestamp ? null : undefined,
    });
    if (!normalized.ok) {
      return normalized;
    }

    if (normalized.wasProvided || hadTimestampField || normalized.value !== null) {
      prepared[column] = normalized.value;
    }
  }

  prepared.sync_status = SERVER_SYNC_STATUS;
  return { ok: true, record: prepared };
}

function isNullableTimestampField(tableName, column) {
  return (
    NULLABLE_TIMESTAMP_COLUMNS.has(column) ||
    NULLABLE_TIMESTAMP_FIELDS.has(`${tableName}.${column}`)
  );
}

function buildRejectedWriteResult(tableName, incomingRecord, existingRecord) {
  if (!existingRecord) {
    return {
      status: 'invalid',
      error: {
        code: 'missing_server_record',
        message: 'The server could not resolve the existing record',
      },
    };
  }

  if (areRecordsEquivalent(tableName, incomingRecord, existingRecord)) {
    return {
      status: 'duplicate',
    };
  }

  const timestampComparison = compareTimestamps(
    incomingRecord.updated_at,
    existingRecord.updated_at,
  );

  const reason =
    timestampComparison < 0
      ? 'stale_update'
      : timestampComparison === 0
      ? 'same_timestamp'
      : 'concurrent_write';

  return {
    status: 'conflict',
    conflict: buildConflictRecord(tableName, incomingRecord, existingRecord, reason),
  };
}

function buildConflictRecord(tableName, incomingRecord, existingRecord, reason) {
  return {
    id: normalizeId(incomingRecord?.id),
    reason,
    incomingUpdatedAt: normalizeTimestamp(incomingRecord?.updated_at),
    serverUpdatedAt: normalizeTimestamp(existingRecord?.updated_at),
    serverRow: canonicalizeRecord(tableName, existingRecord, {
      forceSyncedStatus: true,
    }),
  };
}

function canonicalizeRecord(
  tableName,
  record,
  { forceSyncedStatus = false } = {},
) {
  const config = getTableConfig(tableName);
  const canonical = {};

  if (!record || typeof record !== 'object') {
    if (forceSyncedStatus) {
      canonical.sync_status = SERVER_SYNC_STATUS;
    }
    return canonical;
  }

  for (const column of config.columns) {
    if (tableName === 'users' && column === 'password') {
      continue;
    }

    if (column === 'sync_status') {
      if (
        forceSyncedStatus ||
        Object.prototype.hasOwnProperty.call(record, column)
      ) {
        canonical[column] = SERVER_SYNC_STATUS;
      }
      continue;
    }

    if (!Object.prototype.hasOwnProperty.call(record, column)) {
      continue;
    }
    canonical[column] = canonicalizeValue(column, record[column]);
  }

  if (
    forceSyncedStatus &&
    !Object.prototype.hasOwnProperty.call(canonical, 'sync_status')
  ) {
    canonical.sync_status = SERVER_SYNC_STATUS;
  }

  return canonical;
}

function areRecordsEquivalent(tableName, left, right) {
  const config = getTableConfig(tableName);
  const normalizedLeft = canonicalizeRecord(tableName, left, {
    forceSyncedStatus: true,
  });
  const normalizedRight = canonicalizeRecord(tableName, right, {
    forceSyncedStatus: true,
  });

  return config.columns.every((column) =>
    isSameValue(normalizedLeft[column], normalizedRight[column]),
  );
}

function compareTimestamps(left, right) {
  const leftIso = normalizeTimestamp(left);
  const rightIso = normalizeTimestamp(right);

  if (!leftIso && !rightIso) {
    return 0;
  }
  if (!leftIso) {
    return -1;
  }
  if (!rightIso) {
    return 1;
  }

  const leftMs = Date.parse(leftIso);
  const rightMs = Date.parse(rightIso);

  if (leftMs === rightMs) {
    return 0;
  }
  return leftMs > rightMs ? 1 : -1;
}

function normalizeTimestamp(value) {
  if (value == null) {
    return null;
  }

  if (value instanceof Date) {
    return Number.isNaN(value.getTime()) ? null : value.toISOString();
  }

  const trimmed = String(value).trim();
  if (!trimmed) {
    return null;
  }

  const parsed = new Date(trimmed);
  return Number.isNaN(parsed.getTime()) ? null : parsed.toISOString();
}

function normalizeId(value) {
  const trimmed = value == null ? '' : String(value).trim();
  return trimmed || null;
}

function normalizeTimestampField(value, { field, required, fallback } = {}) {
  const hasValue = !(
    value == null ||
    (typeof value === 'string' && value.trim() === '')
  );

  if (!hasValue) {
    if (fallback !== undefined) {
      return {
        ok: true,
        value: fallback,
        wasProvided: false,
      };
    }
    if (required) {
      return invalidResult('missing_timestamp', `${field} is required`, {
        field,
      });
    }
    return {
      ok: true,
      value: null,
      wasProvided: false,
    };
  }

  const normalized = normalizeTimestamp(value);
  if (!normalized) {
    return invalidResult('invalid_timestamp', `${field} must be a valid timestamp`, {
      field,
    });
  }

  return {
    ok: true,
    value: normalized,
    wasProvided: true,
  };
}

function canonicalizeValue(column, value) {
  if (value === undefined) {
    return null;
  }
  if (column.endsWith('_at')) {
    return normalizeTimestamp(value);
  }
  if (value instanceof Date) {
    return normalizeTimestamp(value);
  }
  return value;
}

function isSameValue(left, right) {
  if (left === right) {
    return true;
  }
  if (left == null && right == null) {
    return true;
  }
  return false;
}

function invalidResult(code, message, extra = {}) {
  return {
    ok: false,
    error: {
      code,
      message,
      ...extra,
    },
  };
}

module.exports = {
  SERVER_SYNC_STATUS,
  buildRejectedWriteResult,
  canonicalizeRecord,
  compareTimestamps,
  prepareIncomingRecord,
};
