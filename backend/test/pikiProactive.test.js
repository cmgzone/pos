const test = require('node:test');
const assert = require('node:assert/strict');

const { buildInsightRowsFromSnapshot } = require('../src/pikiProactive');

test('buildInsightRowsFromSnapshot flags core business risks', () => {
  const insights = buildInsightRowsFromSnapshot(
    {
      branchId: 'main_branch',
      currency: 'KSh',
      lowStock: [
        { name: 'Sugar', stock: 1, low_stock: 5 },
        { name: 'Milk', stock: 0, low_stock: 4 },
      ],
      expiringBatches: [{ name: 'Yoghurt', expiry_date: '2026-05-12' }],
      todaySales: { count: 2, revenue: 1000 },
      yesterdaySales: { count: 10, revenue: 4000 },
      openShifts: [{ cashier_name: 'Amina' }],
      debtors: { count: 3, total: 12000 },
    },
    new Date('2026-05-11T09:00:00.000Z'),
  );

  assert.deepEqual(
    insights.map((insight) => insight.kind),
    ['low_stock', 'expiry_risk', 'sales_drop', 'open_shift', 'customer_debt'],
  );
  assert.equal(insights[0].severity, 'medium');
  assert.equal(insights[2].severity, 'high');
  assert.equal(insights[4].action_json.tool, 'top_debtors');
});

test('buildInsightRowsFromSnapshot returns no alerts for clean snapshot', () => {
  const insights = buildInsightRowsFromSnapshot({
    lowStock: [],
    expiringBatches: [],
    todaySales: { count: 5, revenue: 5000 },
    yesterdaySales: { count: 4, revenue: 4000 },
    openShifts: [],
    debtors: { count: 0, total: 0 },
  });

  assert.equal(insights.length, 0);
});
