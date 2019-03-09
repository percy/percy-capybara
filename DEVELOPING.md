# Developing percy-capybara

You'll need:
* [Ruby](https://www.ruby-lang.org)
* [Bundler](https://bundler.io/)
* [npm](https://www.npmjs.com/), to manage our dependency on [`@percy/agent`](https://www.npmjs.com/package/@percy/agent)

To install dependencies:
```bash
$ bundle install
$ npm install
```

To run our test suite and create snapshots:
```bash
$ bundle exec rake snapshots
```
(You'll need a `PERCY_TOKEN` in your environment for snapshots to be uploaded to Percy for diffing.)

If you want to run the test suite without uploading snapshots, you can run:
```bash
$ bundle exec rspec
```

For instructions on releasing, and on updating the vendored version of `percy-agent.js` in this repository, please refer to the [RELEASING](RELEASING.md) doc.

