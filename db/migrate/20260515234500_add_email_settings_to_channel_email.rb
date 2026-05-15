class AddEmailSettingsToChannelEmail < ActiveRecord::Migration[7.1]
  def change
    add_column :channel_email, :conversation_id_in_subject, :boolean, default: false, null: false
    # 0 = forced_off, 1 = default_off, 2 = default_on, 3 = forced_on
    add_column :channel_email, :include_original_in_reply, :integer, default: 2, null: false
  end
end
