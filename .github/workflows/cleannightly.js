async function clean({ github, context }) {
  console.log(context.payload.repository.owner);
  const rel = await github.rest.repos.getReleaseByTag({
    ...context.repo,
    tag: "nightly",
  });
  const ass = await await github.rest.repos.listReleaseAssets({
    ...context.repo,
    release_id: rel.data.id,
  });
  for (var i = 3; i < ass.data.length; i++) {
    await github.rest.repos.deleteReleaseAsset({
      ...context.repo,
      asset_id: ass.data[i].id,
    });
  }
}

module.exports = ({ github, context }) => clean({ github, context });
