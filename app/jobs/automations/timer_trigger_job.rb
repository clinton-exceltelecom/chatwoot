# Evaluates all active time_elapsed automation rules and fires actions on
# conversations that have crossed the configured time threshold.
#
# Runs every 5 minutes via TriggerScheduledItemsJob / sidekiq-cron.
# Stateless — each run queries current conversation state so it is
# self-healing if the worker is down and recovers later.
class Automations::TimerTriggerJob < ApplicationJob
  queue_as :scheduled_jobs

  # Cap the number of conversations processed per rule per run to avoid
  # runaway queries on large accounts.
  PER_RULE_LIMIT = 500

  def perform
    AutomationRule.timer_rules.find_each(batch_size: 100) do |rule|
      process_rule(rule)
    rescue StandardError => e
      ChatwootExceptionTracker.new(e, account: rule.account).capture_exception
    end
  end

  private

  def process_rule(rule)
    anchor_column = AutomationRule::SCHEDULE_ANCHOR_COLUMN_MAP[rule.schedule_anchor]
    return unless anchor_column

    threshold = rule.schedule_duration_minutes.minutes.ago

    candidate_conversations(rule, anchor_column, threshold).each do |conversation|
      conditions_match = ::AutomationRules::ConditionsFilterService.new(rule, conversation, {}).perform
      next unless conditions_match.present?

      ::AutomationRules::ActionService.new(rule, rule.account, conversation).perform
    rescue StandardError => e
      ChatwootExceptionTracker.new(e, account: rule.account).capture_exception
    end
  end

  # Find conversations whose anchor timestamp is older than the threshold.
  # Excludes conversations without a value for the anchor column (e.g. no first reply yet).
  # Excludes orphan conversations where the contact has been deleted.
  def candidate_conversations(rule, anchor_column, threshold)
    rule.account.conversations
        .where.not(contact_id: nil)
        .where("#{anchor_column} IS NOT NULL")
        .where("#{anchor_column} <= ?", threshold)
        .limit(PER_RULE_LIMIT)
  end
end
