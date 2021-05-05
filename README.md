# percy-capybara
[![Gem Version](https://badge.fury.io/rb/percy-capybara.svg)](https://badge.fury.io/rb/percy-capybara)
![Test](https://github.com/percy/percy-capybara/workflows/Test/badge.svg)

[Percy](https://percy.io) visual testing for Ruby Selenium.

## Installation

npm install `@percy/cli`:

```sh-session
$ npm install --save-dev @percy/cli
```

gem install Percy selenium package:

```ssh-session
$ gem install percy-capybara
```

## Usage

In your test setup file, require `percy/capybara`. For example if you're using
rspec, you would add the following to your `spec_helper.rb` file:


``` ruby
require 'percy/capybara'
```

Now you can use `page.percy_snapshot` to capture snapshots.

> Note: Percy requires JS to be enabled for snapshots to be captured.

```ruby
describe 'my feature, type: :feature, js: true do
  it 'renders the page' do
    visit 'https://example.com'
    page.percy_snapshot('Example snapshot')
  end
end
```


Running the test above normally will result in the following log:

```sh-session
[percy] Percy is not running, disabling snapshots
```

When running with [`percy
exec`](https://github.com/percy/cli/tree/master/packages/cli-exec#percy-exec), and your project's
`PERCY_TOKEN`, a new Percy build will be created and snapshots will be uploaded to your project.

```sh-session
$ export PERCY_TOKEN=[your-project-token]
$ percy exec -- [test command]
[percy] Percy has started!
[percy] Created build #1: https://percy.io/[your-project]
[percy] Snapshot taken "Ruby example"
[percy] Stopping percy...
[percy] Finalized build #1: https://percy.io/[your-project]
[percy] Done!
```

## Configuration

`page.snapshot(name[, options])`

- `name` (**required**) - The snapshot name; must be unique to each snapshot
- `options` - [See per-snapshot configuration options](https://docs.percy.io/docs/cli-configuration#per-snapshot-configuration)

## Upgrading

### Manually

#### Require change

The name of the require has changed from `require 'percy'` to `require
'percy/capybara'`. This is to avoid conflict with our [Ruby Selenium SDK's require](https://github.com/percy/percy-selenium-ruby)
statement.

#### Installing `@percy/cli` & removing `@percy/agent`

If you're coming from a 4.x version of this package, make sure to install `@percy/cli` after
upgrading to retain any existing scripts that reference the Percy CLI
command. You will also want to uninstall `@percy/agent`, as it's been replaced
by `@percy/cli`.

```sh-session
$ npm uninstall @percy/agent
$ npm install --save-dev @percy/cli
```

#### Migrating config

If you have a previous Percy configuration file, migrate it to the newest version with the
[`config:migrate`](https://github.com/percy/cli/tree/master/packages/cli-config#percy-configmigrate-filepath-output) command:

```sh-session
$ percy config:migrate
```
