-- Fix Payment Methods Table
-- Run this to manually create the payment_methods table and seed default data

-- Create payment_methods table
CREATE TABLE IF NOT EXISTS payment_methods (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  is_cash_drawer INTEGER NOT NULL DEFAULT 0,
  is_credit INTEGER NOT NULL DEFAULT 0,
  is_active INTEGER NOT NULL DEFAULT 1,
  sort_order INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  deleted_at TEXT,
  sync_status TEXT NOT NULL DEFAULT 'pending'
);

-- Add is_cash_drawer column to sales table if it doesn't exist
-- Note: SQLite doesn't have IF NOT EXISTS for ALTER TABLE, so this might fail if column exists
-- That's okay - we'll handle the error
ALTER TABLE sales ADD COLUMN is_cash_drawer INTEGER NOT NULL DEFAULT 0;

-- Seed default payment methods
INSERT INTO payment_methods (id, name, is_cash_drawer, is_credit, is_active, sort_order, created_at, updated_at, sync_status)
VALUES 
  ('pm-cash-001', 'Cash', 1, 0, 1, 0, datetime('now'), datetime('now'), 'synced'),
  ('pm-kopesha-001', 'Kopesha', 0, 1, 1, 1, datetime('now'), datetime('now'), 'synced'),
  ('pm-mpesa-001', 'M-Pesa', 0, 0, 1, 2, datetime('now'), datetime('now'), 'synced'),
  ('pm-card-001', 'Card', 0, 0, 1, 3, datetime('now'), datetime('now'), 'synced'),
  ('pm-bank-001', 'Bank Transfer', 0, 0, 1, 4, datetime('now'), datetime('now'), 'synced');

-- Verify the data
SELECT 'Payment Methods Created:' as message;
SELECT name, is_cash_drawer, is_credit, is_active FROM payment_methods ORDER BY sort_order;
