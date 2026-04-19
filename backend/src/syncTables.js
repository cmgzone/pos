const syncTables = [
  {
    name: 'categories',
    columns: [
      'id',
      'name',
      'color',
      'created_at',
      'updated_at',
      'deleted_at',
      'sync_status',
    ],
  },
  {
    name: 'expense_categories',
    columns: [
      'id',
      'name',
      'color',
      'created_at',
      'updated_at',
      'deleted_at',
      'sync_status',
    ],
  },
  {
    name: 'users',
    columns: [
      'id',
      'name',
      'email',
      'phone',
      'password',
      'role',
      'created_at',
      'updated_at',
      'deleted_at',
      'sync_status',
    ],
  },
  {
    name: 'customers',
    columns: [
      'id',
      'name',
      'phone',
      'email',
      'balance',
      'created_at',
      'updated_at',
      'deleted_at',
      'sync_status',
    ],
  },
  {
    name: 'suppliers',
    columns: [
      'id',
      'name',
      'phone',
      'email',
      'address',
      'note',
      'created_at',
      'updated_at',
      'deleted_at',
      'sync_status',
    ],
  },
  {
    name: 'products',
    columns: [
      'id',
      'name',
      'price',
      'cost',
      'stock',
      'low_stock',
      'unit',
      'stock_unit',
      'sale_unit',
      'sale_to_stock_factor',
      'purchase_unit',
      'purchase_to_stock_factor',
      'sku',
      'barcode',
      'image_url',
      'category_id',
      'created_at',
      'updated_at',
      'deleted_at',
      'sync_status',
    ],
  },
  {
    name: 'purchase_invoices',
    columns: [
      'id',
      'supplier_id',
      'supplier_name',
      'invoice_number',
      'total_amount',
      'note',
      'created_at',
      'updated_at',
      'deleted_at',
      'sync_status',
    ],
  },
  {
    name: 'stock_batches',
    columns: [
      'id',
      'product_id',
      'quantity_received',
      'quantity_remaining',
      'unit_cost',
      'purchase_id',
      'supplier_id',
      'received_at',
      'finished_at',
      'created_at',
      'updated_at',
      'deleted_at',
      'sync_status',
    ],
  },
  {
    name: 'sales',
    columns: [
      'id',
      'total_amount',
      'tax',
      'discount',
      'payment_type',
      'user_id',
      'customer_id',
      'customer_name',
      'due_date',
      'amount_paid',
      'amount_tendered',
      'change_given',
      'balance_due',
      'refund_sale_id',
      'refund_for_sale_id',
      'refund_note',
      'refunded_at',
      'created_at',
      'updated_at',
      'deleted_at',
      'sync_status',
    ],
  },
  {
    name: 'sale_items',
    columns: [
      'id',
      'quantity',
      'unit_price',
      'unit_cost',
      'unit',
      'sale_id',
      'product_id',
      'created_at',
      'updated_at',
      'deleted_at',
      'sync_status',
    ],
  },
  {
    name: 'credit_payments',
    columns: [
      'id',
      'payment_group_id',
      'customer_id',
      'sale_id',
      'user_id',
      'amount',
      'note',
      'received_at',
      'created_at',
      'updated_at',
      'deleted_at',
      'sync_status',
    ],
  },
  {
    name: 'expenses',
    columns: [
      'id',
      'category_id',
      'category_name',
      'title',
      'amount',
      'note',
      'incurred_on',
      'created_at',
      'updated_at',
      'deleted_at',
      'sync_status',
    ],
  },
];

const syncTableMap = new Map(syncTables.map((table) => [table.name, table]));

function getTableConfig(tableName) {
  const config = syncTableMap.get(tableName);
  if (!config) {
    throw new Error(`Unsupported sync table: ${tableName}`);
  }
  return config;
}

function sanitizeRecord(tableName, record) {
  const config = getTableConfig(tableName);
  const sanitized = {};

  for (const column of config.columns) {
    if (column === 'sync_status') {
      continue;
    }
    if (Object.prototype.hasOwnProperty.call(record, column)) {
      sanitized[column] = record[column];
    }
  }

  return sanitized;
}

module.exports = {
  syncTables,
  getTableConfig,
  sanitizeRecord,
};
