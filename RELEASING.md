# Releasing

1. Update version.rb file accordingly.
1. Tag the release: `git tag vVERSION`
1. Push changes: `git push --tags`
1. Ensure tests have passed on that tag
1. [Update the release notes](https://github.com/percy/percy-capybara/releases) on GitHub
1. Build and publish:

```bash
bundle exec rake build
gem push pkg/percy-capybara-X.XX.XX.gem
```

* Announce the new release,
   making sure to say "thank you" to the contributors
   who helped shape this version!
