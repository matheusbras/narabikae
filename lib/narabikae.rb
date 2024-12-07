require "narabikae/version"

require "narabikae/active_record_extension"
require "narabikae/configuration"
require "narabikae/option"
require "narabikae/option_store"
require "narabikae/position"

require "fractional_indexer"
require "active_support"
require "active_record"

module Narabikae
  class Error < StandardError; end

  @configuration = Narabikae::Configuration.new

  def self.configure
    yield configuration if block_given?

    configuration
  end

  def self.configuration
    @configuration
  end

  module Extension
    extend ActiveSupport::Concern

    class_methods do
      def narabikae(field = :position, size:, scope: [], insert_at: :last)
        option = narabikae_option_store.register!(
                   field.to_sym,
                   Narabikae::Option.new(field: field, key_max_size: size, scope: scope, insert_at: insert_at)
                 )

        before_create do
          extension = Narabikae::ActiveRecordExtension.new(self, option)
          extension.set_position
        end

        before_update do
          extension = Narabikae::ActiveRecordExtension.new(self, option)
          extension.set_position if extension.auto_set_position?
        end

        define_method :"relative_#{field}=" do |value|
          return if value.blank?

          extension = Narabikae::ActiveRecordExtension.new(self, option)

          if (relative_position = parse_relative_position(value))
            update_position_by_relative(relative_position, field, extension, option)
          else
            update_position_by_keyword(value, field, extension)
          end
        end

        define_method :"set_initial_#{field}" do
          extension = Narabikae::ActiveRecordExtension.new(self, option)
          extension.set_position
        end

        define_method :"move_to_#{field}_after" do |target = nil, **args|
          extension = Narabikae::ActiveRecordExtension.new(self, option)
          extension.move_to_after(target, **args)
        end

        define_method :"move_to_#{field}_before" do |target = nil, **args|
          extension = Narabikae::ActiveRecordExtension.new(self, option)
          extension.move_to_before(target, **args)
        end

        define_method :"move_to_#{field}_between" do |prev_target = nil, next_target = nil, **args|
          extension = Narabikae::ActiveRecordExtension.new(self, option)
          extension.move_to_between(prev_target, next_target, **args)
        end
      end

      private

      def narabikae_option_store
        @_narabikae_option_store ||= Narabikae::OptionStore.new
      end

      def parse_relative_position(value)
        JSON.parse(value, symbolize_names: true)
      rescue JSON::ParserError
        nil
      end

      def update_position_by_relative(relative_position, field, extension, option)
        placement, target_id = *relative_position.first

        case placement
        when :after, :before
          target = find_target(target_id, option)
          update_field_position(field, extension.public_send(:"calculate_position_#{placement}", target))
        else
          prev_target = target_id[0] ? find_target(target_id[0], option) : nil
          next_target = target_id[1] ? find_target(target_id[1], option) : nil
          update_field_position(field, extension.calculate_position_between(prev_target, next_target))
        end
      end

      def update_position_by_keyword(value, field, extension)
        case value
        when "first"
          update_field_position(field, extension.create_first_position)
        when "last"
          update_field_position(field, extension.create_last_position)
        end
      end

      def find_target(id, option)
        self.class.where(slice(*option.scope)).find(id)
      end

      def update_field_position(field, new_position)
        send(:"#{field}_will_change!")
        send(:"#{field}=", new_position)
      end
    end
  end
end

ActiveSupport.on_load :active_record do |base|
  base.include Narabikae::Extension
end
