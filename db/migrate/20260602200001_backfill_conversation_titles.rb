class BackfillConversationTitles < ActiveRecord::Migration[7.1]
  def up
    execute <<-SQL.squish
      UPDATE conversations
      SET title = additional_attributes->>'mail_subject'
      WHERE additional_attributes->>'mail_subject' IS NOT NULL
        AND additional_attributes->>'mail_subject' != ''
        AND title IS NULL
    SQL
  end

  def down
    # No-op: we don't remove backfilled data
  end
end
