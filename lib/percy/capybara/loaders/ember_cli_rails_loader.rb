# frozen_string_literal: true

require 'percy/capybara/loaders/sprockets_loader'

module Percy
  module Capybara
    module Loaders
      class EmberCliRailsLoader < SprocketsLoader
        attr_reader :mounted_apps

        EMBER_ASSETS_DIR = 'assets'

        def initialize(mounted_apps, options = {})
          super(options)

          @mounted_apps = mounted_apps
        end

        def build_resources
          resources = []

          @mounted_apps.map do |app_name, mount_path|
            # public assets path for this particular ember app. If the app is mounted on /admin
            # the output would be: /admin/assets
            base_assets_url = File.join(mount_path, EMBER_ASSETS_DIR)

            # full path on disk to the assets for this ember app
            # e.g. /Users/djones/Code/rails-ember-app/tmp/ember-cli/apps/frontend
            dist_path = _ember_cli.apps[app_name].dist_path

            # full path to the directory on disk where ember stores assets for this ember app
            # e.g. /Users/djones/Code/rails-ember-app/tmp/ember-cli/apps/frontend/assets
            ember_assets_path = File.join(dist_path, EMBER_ASSETS_DIR)

            resources += _resources_from_path(ember_assets_path, base_url: base_assets_url)
          end

          resources += super # adds sprockets resources from Rails
        end

        def _ember_cli
          EmberCli if defined?(EmberCli)
        end
      end
    end
  end
end
