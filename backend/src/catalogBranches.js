function normalizePublicCatalogBranches(rows = []) {
  const branches = rows.map((branch) => ({
    id: branch.id,
    name: branch.name || (branch.id === 'main_branch' ? 'Main' : branch.id),
  }));

  if (!branches.some((branch) => branch.id === 'main_branch')) {
    branches.unshift({ id: 'main_branch', name: 'Main' });
  }

  return branches;
}

module.exports = {
  normalizePublicCatalogBranches,
};
