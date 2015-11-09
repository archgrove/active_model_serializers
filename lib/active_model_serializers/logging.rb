##
# Adapted from:
#   https://github.com/rubygems/rubygems/blob/cb28f5e991/lib/rubygems/deprecate.rb
#   https://github.com/rails/rails/blob/280654ef88/activejob/lib/active_job/logging.rb
#
# Provides a single method +notify+ to be used to declare when
# something a method notifies.
#
#     class Adapter
#       def self.klass_method
#         # ...
#       end
#
#       def instance_method
#         # ...
#       end
#
#       extend ActiveModelSerializers::Logging
#       notify :instance_method, :render
#
#       class << self
#         extend ActiveModelSerializers::Logging
#         notify :klass_method, :render
#       end
#     end
module ActiveModelSerializers::Logging
  extend ActiveSupport::Concern

  included do
    include ActiveSupport::Callbacks
    instrument_around_render
  end

  module ClassMethods
    def instrument_around_render
      define_callbacks :render
      around_render do |args, block|
        tag_logger do
          notify_render do
            block.call(args)
          end
        end
      end
    end

    def around_render(*filters, &blk)
      set_callback(:render, :around, *filters, &blk)
    end

    ##
    # Simple notify method that wraps up +name+
    # in a dummy method. It notifies on with the +callback_name+ notifier on
    # each call to the dummy method, telling what the current serializer and adapter
    # are being rendered.
    # Adapted from:
    #   https://github.com/rubygems/rubygems/blob/cb28f5e991/lib/rubygems/deprecate.rb
    def notify(name, callback_name)
      class_eval do
        old = "_notifying_#{callback_name}_#{name}"
        alias_method old, name
        define_method name do |*args, &block|
          run_callbacks callback_name do
            send old, *args, &block
          end
        end
      end
    end
  end

  def notify_render(*)
    event_name = 'render.active_model_serializers'.freeze
    ActiveSupport::Notifications.instrument(event_name, notify_render_payload) do
      yield
    end
  end

  def notify_render_payload
    { serializer: serializer, adapter: adapter }
  end

  private

  def tag_logger(*tags)
    if ActiveModelSerializers.logger.respond_to?(:tagged)
      tags.unshift 'AMS'.freeze unless logger_tagged_by_active_model_serializers?
      ActiveModelSerializers.logger.tagged(*tags) { yield }
    else
      yield
    end
  end

  def logger_tagged_by_active_model_serializers?
    ActiveModelSerializers.logger.formatter.current_tags.include?('AMS'.freeze)
  end

  class LogSubscriber < ActiveSupport::LogSubscriber
    def render(event)
      info do
        serializer = event.payload[:serializer]
        adapter = event.payload[:adapter]
        duration = event.duration.round(2)
        "Rendered #{serializer.name} with #{adapter.class} (#{duration}ms)"
      end
    end

    def logger
      ActiveModelSerializers.logger
    end
  end
end

ActiveModelSerializers::Logging::LogSubscriber.attach_to :active_model_serializers
