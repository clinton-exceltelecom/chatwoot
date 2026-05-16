<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useUISettings } from 'dashboard/composables/useUISettings';

const { t } = useI18n();
const { uiSettings, updateUISettings } = useUISettings();

const currentValue = computed(
  () => uiSettings.value.conversation_list_preview || 'message'
);

const options = [
  {
    value: 'message',
    label: t(
      'PROFILE_SETTINGS.FORM.INTERFACE_SECTION.CONVERSATION_LIST_PREVIEW.OPTIONS.MESSAGE'
    ),
  },
  {
    value: 'subject',
    label: t(
      'PROFILE_SETTINGS.FORM.INTERFACE_SECTION.CONVERSATION_LIST_PREVIEW.OPTIONS.SUBJECT'
    ),
  },
  {
    value: 'both',
    label: t(
      'PROFILE_SETTINGS.FORM.INTERFACE_SECTION.CONVERSATION_LIST_PREVIEW.OPTIONS.BOTH'
    ),
  },
];

const onChange = event => {
  updateUISettings({ conversation_list_preview: event.target.value });
};
</script>

<template>
  <div class="flex flex-col gap-1">
    <label class="text-sm font-medium text-n-slate-12">
      {{
        $t(
          'PROFILE_SETTINGS.FORM.INTERFACE_SECTION.CONVERSATION_LIST_PREVIEW.TITLE'
        )
      }}
    </label>
    <p class="text-xs text-n-slate-11 mb-1">
      {{
        $t(
          'PROFILE_SETTINGS.FORM.INTERFACE_SECTION.CONVERSATION_LIST_PREVIEW.NOTE'
        )
      }}
    </p>
    <select :value="currentValue" class="mb-0 max-w-xs" @change="onChange">
      <option
        v-for="option in options"
        :key="option.value"
        :value="option.value"
      >
        {{ option.label }}
      </option>
    </select>
  </div>
</template>
