# Releasing

1. `git checkout master`
1. `git pull origin master`
1. `git checkout -b X.X.X`
1. Update version.rb file accordingly.
1. Commit and push the version update
1. Tag the release: `git tag vX.X.X`
1. Push changes: `git push --tags`
1. Ensure tests have passed on that tag
1. Open up a pull request titled with the new version number
1. Merge approved pull request
1. Draft and publish a [new release on github](https://github.com/percy/percy-capybara/releases)
1. Build and publish:

```bash
bundle exec rake build
gem push pkg/percy-capybara-X.XX.XX.gem
```

* Announce the new release,
   making sure to say "thank you" to the contributors
   who helped shape this version!
