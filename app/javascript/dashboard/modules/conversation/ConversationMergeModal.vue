<script setup>
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'vuex';
import { useAlert } from 'dashboard/composables';

const props = defineProps({
  currentConversationDisplayId: {
    type: Number,
    required: true,
  },
  sourceConversation: {
    type: Object,
    required: true,
  },
});

const emit = defineEmits(['close', 'merged']);

const { t } = useI18n();
const store = useStore();
const isMerging = ref(false);

const onConfirm = async () => {
  isMerging.value = true;
  try {
    await store.dispatch('mergeConversation', {
      sourceId: props.sourceConversation.display_id,
      targetId: props.currentConversationDisplayId,
    });
    useAlert(t('CONVERSATION.MERGE_CONVERSATION.SUCCESS'));
    emit('merged');
    emit('close');
  } catch {
    useAlert(t('CONVERSATION.MERGE_CONVERSATION.ERROR'));
  } finally {
    isMerging.value = false;
  }
};
</script>

<template>
  <div
    class="fixed inset-0 z-50 flex items-center justify-center bg-black/40"
    @click.self="emit('close')"
  >
    <div
      class="bg-n-solid-1 rounded-xl shadow-xl w-full max-w-md mx-4 p-6 flex flex-col gap-4"
    >
      <h3 class="text-base font-semibold text-n-slate-12">
        {{
          $t('CONVERSATION.MERGE_CONVERSATION.CONFIRM_TITLE', {
            sourceId: sourceConversation.display_id,
            targetId: currentConversationDisplayId,
          })
        }}
      </h3>
      <p class="text-sm text-n-slate-11 mb-0">
        {{
          $t('CONVERSATION.MERGE_CONVERSATION.CONFIRM_DESCRIPTION', {
            sourceId: sourceConversation.display_id,
          })
        }}
      </p>
      <div class="flex justify-end gap-2 mt-2">
        <button
          class="px-4 py-2 text-sm rounded-lg text-n-slate-11 hover:bg-n-alpha-2 transition-colors"
          @click="emit('close')"
        >
          {{ $t('CONVERSATION.MERGE_CONVERSATION.CANCEL') }}
        </button>
        <button
          class="px-4 py-2 text-sm font-medium rounded-lg bg-n-ruby-9 text-white hover:bg-n-ruby-10 transition-colors disabled:opacity-50"
          :disabled="isMerging"
          @click="onConfirm"
        >
          {{
            isMerging
              ? $t('CONVERSATION.MERGE_CONVERSATION.CONFIRM_MERGING')
              : $t('CONVERSATION.MERGE_CONVERSATION.CONFIRM')
          }}
        </button>
      </div>
    </div>
  </div>
</template>
