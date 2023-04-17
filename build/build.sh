#!/bin/bash -e

# Builds a versioned zip file suitable for distribution. The only step other
# than zipping is substituting a version number in Info.lua.
# This script expects to be run from the top level directory of a git
# repository.

GITHUB_OUTPUT=${GITHUB_OUTPUT:=/dev/fd/0}

src=lr-inaturalist-publish.lrdevplugin
name=lr-inaturalist-publish
plug=${name}.lrplugin

description=$(git describe --match "v[0-9]*.[0-9]*.[0-9]*" --exclude 'v*[!0-9.]*' --long --dirty)
last_tag=${description%%-*}
commits_since_tag=${description%-*}
commits_since_tag=${commits_since_tag#*-}
hash=${description##*-}
branch="$(git branch --show-current)"

version="${last_tag#v}"
v="{ major = ${version} }"
# Replace dots one at a time
v="${v/./, minor = }"
v="${v/./, revision = }"
if [ "$commits_since_tag" != "0" ] ; then
  if [ "$branch" = "main" ] ; then
    branch=dev
  else
    branch="branch.$branch"
  fi
  next_patch=$(( ${last_tag##*.} + 1 ))
  next_ver="${last_tag%.*}.${next_patch}"
  version=${next_ver#v}-${branch}.${commits_since_tag}.${hash}
  v="${v% \}}, build = \"${branch}.${commits_since_tag}.${hash}\", display = \"${version}\" }"
fi

mkdir -p build
cd build || exit
rm -rf "$plug"
cp -pr ../"$src" "$plug"
# sed on macOS and Linux have different behaviours with -i. Use perl instead.
perl -pi -e "s/VERSION = DEV_VERSION/VERSION = $v/" "${plug}/Info.lua"
zip -X9vr "${name}-${version}".zip "${plug}"

echo "built_name=${name}-${version}" >> "$GITHUB_OUTPUT"
echo "built_zip=build/${name}-${version}.zip" >> "$GITHUB_OUTPUT"
