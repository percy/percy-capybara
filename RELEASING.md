# Releasing

- [Releasing](#releasing)
  - [Make a release](#make-a-release)
  - [Updating the vendorized version of percy-agent.js](#updating-the-vendorized-version-of-percy-agentjs)

## Make a release

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

## Updating the vendorized version of percy-agent.js

The `percy-agent.js` file in this repo is a copy of the one distributed with the `@percy/agent` npm package. To update it:

1. Bump the `@percy/agent` version to the one you want:
```bash
$ npm install --save-dev @percy/agent@<DESIRED VERSION>
```

2. Use the `vendorize` npm script to copy the file to the `vendor/` directory:
```bash
$ npm run vendorize
```

3. Commit your changes.
4. Make a new release with the new percy-agent.js version.
