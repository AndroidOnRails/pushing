module Fourseam
  class Base < AbstractController::Base
    include PlatformSupport
    include Rescuable

    abstract!

    include AbstractController::Rendering
    include AbstractController::Logger
    include AbstractController::Helpers
    include AbstractController::Translation
    include AbstractController::AssetPaths
    include AbstractController::Callbacks
    begin
      include AbstractController::Caching
    rescue NameError
      # AbstractController::Caching does not exist in rails 4.2. No-op.
    end

    include ActionView::Layouts

    PROTECTED_IVARS = AbstractController::Rendering::DEFAULT_PROTECTED_INSTANCE_VARIABLES + [:@_action_has_layout]

    def _protected_ivars # :nodoc:
      PROTECTED_IVARS
    end

    helper Fourseam::NotificationHelper

    cattr_accessor :deliver_later_queue_name
    self.deliver_later_queue_name = :notifiers

    class << self
      delegate :deliveries, :deliveries=, to: Fourseam::Adapters::TestAdapter

      def notifier_name
        @notifier_name ||= anonymous? ? "anonymous" : name.underscore
      end
      # Allows to set the name of current notifier.
      attr_writer :notifier_name
      alias :controller_path :notifier_name

      def method_missing(method_name, *args)
        if action_methods.include?(method_name.to_s)
          NotificationDelivery.new(self, method_name, *args)
        else
          super
        end
      end

      def respond_to_missing?(method, include_all = false)
        action_methods.include?(method.to_s) || super
      end
    end

    def process(method_name, *args) #:nodoc:
      payload = {
        notifier: self.class.name,
        action: method_name,
        args: args
      }

      ActiveSupport::Notifications.instrument("process.push_notification", payload) do
        super
        @_notification ||= NullNotification.new
      end
    end

    class NullNotification #:nodoc:
      def respond_to?(string, include_all = false)
        true
      end

      def method_missing(*args)
        nil
      end
    end

    attr_internal :notification

    def push(headers = {}, &block)
      return notification if notification && headers.blank? && !block

      payload = headers.reduce({}) do |acc, (platform, options)|
        lookup_context.variants = platform
        json = collect_responses(headers, &block)

        acc.update(platform => build_payload(platform, json, options))
      end

      # TODO: Do not use OpenStruct
      @_notification = OpenStruct.new(payload)
    end

    private

    def collect_responses(headers)
      #if block_given?
      #  collector = Fourseam::Collector.new(lookup_context) { render(action_name) }
      #  yield(collector)
      #  collector.responses
      #elsif headers[:body]
      #  collect_responses_from_text(headers)
      #else
        collect_responses_from_templates(headers)
      #end
    end

    def collect_responses_from_templates(headers)
      templates_path = headers[:template_path] || self.class.notifier_name
      templates_name = headers[:template_name] || action_name

      template = lookup_context.find(templates_name, Array(templates_path))
      render(template: template)
    end
  end
end
