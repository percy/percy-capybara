module Percy
  module Capybara
    class ConfigLoader
      DOTFILE = '.percy-capybara.yml'.freeze
      PERCY_CAPYBARA_HOME = File.realpath(File.join(File.dirname(__FILE__), '..', '..', '..'))
      DEFAULT_FILE = File.join(PERCY_CAPYBARA_HOME, 'config', 'default.yml')

      class << self
        def load_default
          load_yaml_configuration(DEFAULT_FILE)
        end

        def load_yaml_configuration(absolute_path)
          yaml_code = IO.read(absolute_path, encoding: 'UTF-8')
          # At one time, there was a problem with the psych YAML engine under
          # Ruby 1.9.3. YAML.load_file would crash when reading empty .yml files
          # or files that only contained comments and blank lines. This problem
          # is not possible to reproduce now, but we want to avoid it in case
          # it's still there. So we only load the YAML code if we find some real
          # code in there.
          hash = yaml_code =~ /^[A-Z]/i ? yaml_safe_load(yaml_code) : {}
          
          raise(TypeError, "Malformed configuration in #{absolute_path}") unless hash.is_a?(Hash)

          hash
        end

        # Rails
        def load_rails_dotfile
          load_yaml_configuration(rails_dotfile) if rails_dotfile_exists?
        end

        def rails_dotfile
          Rails.root.join(DOTFILE)
        end

        def rails_dotfile_exists?
          File.exist?(rails_dotfile)
        end

        # @private
        def yaml_safe_load(yaml_code)
          if YAML.respond_to?(:safe_load) # Ruby 2.1+
            YAML.safe_load(yaml_code)
          else
            YAML.load(yaml_code)
          end
        end
      end
    end
  end
end
