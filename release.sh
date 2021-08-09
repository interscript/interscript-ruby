#!/bin/bash
set -euo pipefail

# We assume this is executed in the main Interscript repository root directory.
# Adjust the V to reflect a correct version
echo -n "Version(2.x.x):"
read V

# Adjust the B to reflect a correct branch name. For now, master. In the future we may decide on
# how to do stable branches.
B="master"

# Ensure we are on the latest repository version and all subrepos are up to date as well.
git checkout $B; git pull; git reset
pushd js; git checkout $B; git pull; git reset; popd
pushd maps; git checkout $B; git pull; git reset; popd
# This is the point when you may want to run tests and ensure everything is correct.
# Run the version update script
pushd ruby; bundle exec rake version[$V]; popd
# Add the new version to the submodules, commit it and tag it
pushd js; git add package.json; git commit -m "Release v$V"; git tag "v$V"; popd
pushd maps; git add interscript-maps.gemspec; git commit -m "Release v$V"; git tag "v$V"; popd
# Add the new version and submodules to the main repo, commit it and tag it
git add js maps ruby/lib/interscript/version.rb; git commit -m "Release v$V"; git tag "v$V"

# Push everything in the correct order
echo "Push js repo..."
pushd js; git push; git push --tags; popd
echo "Push map repo..."
pushd maps; git push; git push --tags; popd
echo "Push main repo..."
git push; git push --tags

# Our new version is released!
echo "Our new version $V is released!"
