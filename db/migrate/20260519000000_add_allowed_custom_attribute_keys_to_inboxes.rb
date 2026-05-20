# frozen_string_literal: true

class AddAllowedCustomAttributeKeysToInboxes < ActiveRecord::Migration[7.0]
  def change
    add_column :inboxes, :allowed_custom_attribute_keys, :jsonb, default: []
  end
end
