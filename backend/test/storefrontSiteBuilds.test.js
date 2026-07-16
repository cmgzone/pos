const test = require('node:test');
const assert = require('node:assert/strict');

const {
  createStorefrontSiteBuild,
  publishStorefrontSiteBuild,
  storefrontSiteBuildSummary,
} = require('../src/storefrontSiteBuilds');
const { compileStorefrontSitePackage } = require('../src/storefrontSiteCompiler');

test('generated site builds are compiled, versioned, and stored as drafts', async () => {
  const statements = [];
  const target = async (sql, params = []) => {
    statements.push(sql);
    if (/CREATE TABLE|CREATE INDEX|CREATE UNIQUE INDEX/i.test(sql)) return { rows: [] };
    if (/pg_advisory_xact_lock/i.test(sql)) return { rows: [{}] };
    if (/MAX\(version\)/i.test(sql)) return { rows: [{ next_version: 4 }] };
    if (/INSERT INTO storefront_site_builds/i.test(sql)) {
      return {
        rows: [{
          id: params[0],
          business_id: params[1],
          branch_id: params[2],
          storefront_type: params[3],
          version: params[4],
          name: params[5],
          summary: params[6],
          instruction: params[7],
          source_json: JSON.parse(params[8]),
          compiled_json: JSON.parse(params[9]),
          compiler_version: params[10],
          code_hash: params[11],
          status: 'draft',
          source: params[12],
          parent_build_id: params[13],
          created_by: params[14],
        }],
      };
    }
    throw new Error(`Unexpected SQL in test: ${sql}`);
  };

  const build = await createStorefrontSiteBuild(
    target,
    'business-1',
    {
      branchId: 'main_branch',
      storefrontType: 'retail',
      instruction: 'Create a clean image-first shop.',
      parentBuildId: 'build-previous',
      package: {
        name: 'New custom shop',
        summary: 'A custom shop.',
        html: '<main><piki-products></piki-products></main>',
        css: 'main{max-width:1200px;margin:auto}',
      },
    },
    { createdBy: 'manager-1' },
  );

  assert.equal(build.version, 4);
  assert.equal(build.status, 'draft');
  assert.equal(build.parentBuildId, 'build-previous');
  assert.equal(build.security.passed, true);
  assert.equal(build.createdBy, 'manager-1');
  assert.ok(statements.some((sql) => /pg_advisory_xact_lock/i.test(sql)));

  const summary = storefrontSiteBuildSummary(build);
  assert.equal(summary.html, undefined);
  assert.equal(summary.pageHtml, undefined);
  assert.equal(summary.css, undefined);
  assert.equal(summary.codeHash, build.codeHash);
});

test('publishing revalidates the immutable generated code hash', async () => {
  const compiled = compileStorefrontSitePackage({
    name: 'Verified site',
    html: '<piki-products></piki-products>',
    css: 'piki-products{display:grid}',
  });
  const row = {
    id: 'build-verified',
    business_id: 'business-1',
    branch_id: 'main_branch',
    storefront_type: 'retail',
    version: 2,
    name: compiled.name,
    summary: compiled.summary,
    compiled_json: compiled,
    compiler_version: compiled.compilerVersion,
    code_hash: compiled.codeHash,
    status: 'draft',
  };
  let published = false;
  const target = async (sql) => {
    if (/CREATE TABLE|CREATE INDEX|CREATE UNIQUE INDEX/i.test(sql)) return { rows: [] };
    if (/SELECT \* FROM storefront_site_builds/i.test(sql)) return { rows: [row] };
    if (/WITH archived AS/i.test(sql)) {
      published = true;
      return { rows: [{ ...row, status: 'published' }] };
    }
    throw new Error(`Unexpected SQL in test: ${sql}`);
  };

  const build = await publishStorefrontSiteBuild(
    target,
    'business-1',
    row.id,
  );
  assert.equal(build.status, 'published');
  assert.equal(published, true);

  const tamperedTarget = async (sql) => {
    if (/CREATE TABLE|CREATE INDEX|CREATE UNIQUE INDEX/i.test(sql)) return { rows: [] };
    if (/SELECT \* FROM storefront_site_builds/i.test(sql)) {
      return {
        rows: [{
          ...row,
          compiled_json: {
            ...compiled,
            html: '<main>Changed after compilation<piki-products></piki-products></main>',
          },
        }],
      };
    }
    throw new Error('Tampered code must not reach the publish query.');
  };
  await assert.rejects(
    publishStorefrontSiteBuild(tamperedTarget, 'business-1', row.id),
    /no longer passes the current compiler/i,
  );
});
