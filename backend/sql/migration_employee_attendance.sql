CREATE TABLE IF NOT EXISTS employee_attendance (
  id text PRIMARY KEY, business_id text, branch_id text, user_id text NOT NULL,
  user_name text, clock_in_at timestamptz NOT NULL, clock_out_at timestamptz,
  note text, status text NOT NULL DEFAULT 'open', server_revision bigint NOT NULL DEFAULT nextval('sync_revision_seq'),
  created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
  deleted_at timestamptz, sync_status text NOT NULL DEFAULT 'synced'
);
CREATE INDEX IF NOT EXISTS idx_employee_attendance_branch_user ON employee_attendance(business_id, branch_id, user_id, clock_in_at DESC);
