class AddScheduleFieldsToAutomationRules < ActiveRecord::Migration[7.1]
  def change
    add_column :automation_rules, :schedule_anchor, :string
    add_column :automation_rules, :schedule_duration_minutes, :integer

    add_index :automation_rules, :schedule_anchor, where: "schedule_anchor IS NOT NULL"
  end
end
