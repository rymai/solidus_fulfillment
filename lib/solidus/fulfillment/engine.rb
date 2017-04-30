module Solidus
  module Fulfillment
    class Engine < Rails::Engine
      isolate_namespace Spree
      engine_name 'solidus_fulfillment'

      config.to_prepare do
        Dir.glob(File.join(__dir__, '../../../app/**/*_decorator*.rb')) do |c|
          require_dependency(c)
        end
      end
    end
  end
end
