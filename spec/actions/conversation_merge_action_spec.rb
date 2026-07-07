require 'rails_helper'

describe ConversationMergeAction do
  subject(:conversation_merge) do
    described_class.new(
      account: account,
      base_conversation: base_conversation,
      mergee_conversation: mergee_conversation
    ).perform
  end

  let!(:account) { create(:account) }
  let!(:contact) { create(:contact, account: account) }
  let!(:inbox) { create(:inbox, account: account) }
  let!(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox) }

  let!(:base_conversation) do
    create(:conversation, account: account, contact: contact, inbox: inbox, contact_inbox: contact_inbox)
  end

  let!(:mergee_conversation) do
    create(:conversation, account: account, contact: contact, inbox: inbox, contact_inbox: contact_inbox)
  end

  describe '#perform' do
    context 'when base and mergee are the same conversation' do
      it 'returns the conversation without any changes' do
        result = described_class.new(
          account: account,
          base_conversation: base_conversation,
          mergee_conversation: base_conversation
        ).perform

        expect(result).to eq(base_conversation)
      end
    end

    context 'when conversations belong to a different account' do
      it 'raises an error' do
        other_account = create(:account)
        expect do
          described_class.new(
            account: other_account,
            base_conversation: base_conversation,
            mergee_conversation: mergee_conversation
          ).perform
        end.to raise_error(StandardError, 'conversation does not belong to the account')
      end
    end

    context 'when conversations belong to different contacts' do
      it 'raises an error' do
        other_contact = create(:contact, account: account)
        other_conversation = create(:conversation, account: account, contact: other_contact)

        expect do
          described_class.new(
            account: account,
            base_conversation: base_conversation,
            mergee_conversation: other_conversation
          ).perform
        end.to raise_error(StandardError, 'conversations do not belong to the same contact')
      end
    end

    context 'when moving messages' do
      it 'moves non-activity messages from mergee to base conversation' do
        incoming = create(:message, conversation: mergee_conversation, account: account, inbox: inbox, message_type: :incoming)
        outgoing = create(:message, conversation: mergee_conversation, account: account, inbox: inbox, message_type: :outgoing)

        conversation_merge

        # Both messages should now belong to base
        expect(base_conversation.messages.non_activity_messages.map(&:id)).to include(incoming.id, outgoing.id)
        # No non-activity messages should remain on mergee
        expect(mergee_conversation.messages.non_activity_messages.count).to eq(0)
      end

      it 'does not move activity messages from mergee to base conversation' do
        create(:message, conversation: mergee_conversation, account: account, inbox: inbox, message_type: :activity)

        conversation_merge

        expect(mergee_conversation.messages.where(message_type: :activity).count).to be >= 1
      end
    end

    context 'when merging labels' do
      it 'combines labels from both conversations' do
        base_conversation.update!(label_list: %w[billing urgent])
        mergee_conversation.update!(label_list: %w[technical urgent])

        conversation_merge
        base_conversation.reload

        expect(base_conversation.label_list).to include('billing', 'urgent', 'technical')
      end

      it 'deduplicates labels' do
        base_conversation.update!(label_list: %w[billing])
        mergee_conversation.update!(label_list: %w[billing])

        conversation_merge
        base_conversation.reload

        expect(base_conversation.label_list.count('billing')).to eq(1)
      end
    end

    context 'when moving participants' do
      it 'moves unique participants from mergee to base conversation' do
        agent = create(:user, account: account, role: :agent)
        create(:inbox_member, user: agent, inbox: inbox)
        create(:conversation_participant, conversation: mergee_conversation, user: agent)

        expect { conversation_merge }
          .to change { base_conversation.conversation_participants.count }.by(1)
      end

      it 'does not duplicate existing participants' do
        agent = create(:user, account: account, role: :agent)
        create(:inbox_member, user: agent, inbox: inbox)
        create(:conversation_participant, conversation: base_conversation, user: agent)
        create(:conversation_participant, conversation: mergee_conversation, user: agent)

        expect { conversation_merge }
          .not_to(change { base_conversation.conversation_participants.count })
      end
    end

    context 'when creating activity messages' do
      it 'creates an activity message on the base conversation' do
        conversation_merge

        activity = base_conversation.messages.where(message_type: :activity).last
        expect(activity.content).to include(mergee_conversation.display_id.to_s)
      end

      it 'creates an activity message on the mergee conversation' do
        conversation_merge

        activity = mergee_conversation.messages.where(message_type: :activity).last
        expect(activity.content).to include(base_conversation.display_id.to_s)
      end
    end

    context 'when resolving the mergee conversation' do
      it 'resolves the mergee conversation' do
        conversation_merge

        expect(mergee_conversation.reload.status).to eq('resolved')
      end

      it 'does not change the base conversation status' do
        conversation_merge

        expect(base_conversation.reload.status).to eq('open')
      end
    end

    it 'returns the base conversation' do
      result = conversation_merge

      expect(result).to eq(base_conversation)
    end
  end
end
