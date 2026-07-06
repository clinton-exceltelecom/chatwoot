class ConversationMergeAction
  include Events::Types
  pattr_initialize [:account!, :base_conversation!, :mergee_conversation!]

  def perform
    return @base_conversation if @base_conversation.id == @mergee_conversation.id

    ActiveRecord::Base.transaction do
      validate_conversations
      move_messages
      move_labels
      move_participants
      create_activity_on_base
      resolve_mergee_conversation
    end

    @base_conversation
  end

  private

  def validate_conversations
    unless belongs_to_account?(@base_conversation) && belongs_to_account?(@mergee_conversation)
      raise StandardError, 'conversation does not belong to the account'
    end

    return unless @base_conversation.contact_id != @mergee_conversation.contact_id

    raise StandardError, 'conversations do not belong to the same contact'
  end

  def belongs_to_account?(conversation)
    @account.id == conversation.account_id
  end

  def move_messages
    # rubocop:disable Rails/SkipsModelValidations
    @mergee_conversation.messages
                        .where(message_type: Message.message_types.except('activity').values)
                        .update_all(
                          conversation_id: @base_conversation.id,
                          inbox_id: @base_conversation.inbox_id
                        )
    # rubocop:enable Rails/SkipsModelValidations
  end

  def move_labels
    existing_labels = @base_conversation.label_list
    mergee_labels = @mergee_conversation.label_list
    combined_labels = (existing_labels + mergee_labels).uniq

    @base_conversation.label_list = combined_labels
    @base_conversation.save!
  end

  def move_participants
    mergee_participant_ids = @mergee_conversation.conversation_participants.pluck(:user_id)
    existing_participant_ids = @base_conversation.conversation_participants.pluck(:user_id)
    new_participant_ids = mergee_participant_ids - existing_participant_ids

    new_participant_ids.each do |user_id|
      @base_conversation.conversation_participants.find_or_create_by!(user_id: user_id)
    end
  end

  def create_activity_on_base
    content = I18n.t(
      'conversations.activity.merged',
      display_id: @mergee_conversation.display_id
    )
    @base_conversation.messages.create!(
      message_type: :activity,
      account_id: @account.id,
      inbox_id: @base_conversation.inbox_id,
      content: content
    )
  end

  def resolve_mergee_conversation
    content = I18n.t(
      'conversations.activity.merged_source',
      display_id: @base_conversation.display_id
    )
    @mergee_conversation.messages.create!(
      message_type: :activity,
      account_id: @account.id,
      inbox_id: @mergee_conversation.inbox_id,
      content: content
    )
    @mergee_conversation.update!(status: :resolved)
  end
end
