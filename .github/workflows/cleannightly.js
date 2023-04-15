async function clean({ github, context }) {
  const tag = "nightly";
  const rel = await github.rest.repos.getReleaseByTag({
    ...context.repo,
    tag: tag,
  });
  const assetResp = await await github.rest.repos.listReleaseAssets({
    ...context.repo,
    release_id: rel.data.id,
  });
  const assets = assetResp.data.sort((a, b) =>
    a.created_at < b.created_at ? 1 : b.created_at < a.created_at ? -1 : 0
  );
  for (var i = 3; i < assets.length; i++) {
    await github.rest.repos.deleteReleaseAsset({
      ...context.repo,
      asset_id: assets[i].id,
    });
  }

  // Now move the "nightly" tag
  await github.rest.git.updateRef({
    ...context.repo,
    ref: `tags/${tag}`,
    sha: context.sha,
  });
}

module.exports = ({ github, context }) => clean({ github, context });
