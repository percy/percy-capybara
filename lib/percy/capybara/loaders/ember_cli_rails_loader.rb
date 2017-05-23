require 'percy/capybara/loaders/sprockets_loader'
require 'set'

module Percy
  module Capybara
    module Loaders
      class EmberCliRailsLoader < SprocketsLoader
        attr_reader :mounted_apps

        def initialize(mounted_apps, options = {})
          super(options)

          raise 'mounted_apps is required' unless mounted_apps
          @mounted_apps = mounted_apps
        end

        def build_resources
          resources = super # adds sprockets resources first

          sprockets_resource_urls = resources.collect(&:resource_url)
          loaded_resource_urls = Set.new(sprockets_resource_urls)

          @mounted_apps.map do |app_name, mount_path|
            # full path on disk to this ember app
            # e.g. /Users/djones/Code/rails-ember-app/tmp/ember-cli/apps/frontend
            dist_path = _dist_path_for_app(app_name)

            resources_from_dir = _resources_from_dir(dist_path, base_url: mount_path)

            resources_from_dir.each do |resource|
              # avoid loading in duplicate resource_urls
              next if loaded_resource_urls.include? resource.resource_url

              resources << resource
              loaded_resource_urls << resource.resource_url
            end
          end

          resources
        end

        def _dist_path_for_app(app_name)
          _ember_cli.apps[app_name].dist_path
        end

        def _ember_cli
          EmberCli if defined?(EmberCli)
        end
      end
    end
  end
end
