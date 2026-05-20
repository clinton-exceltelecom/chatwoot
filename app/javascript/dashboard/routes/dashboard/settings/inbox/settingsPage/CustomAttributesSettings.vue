<script setup>
import { computed, ref, watch } from 'vue';
import { useStore, useStoreGetters } from 'dashboard/composables/store';
import { useI18n } from 'vue-i18n';
import SettingsToggleSection from 'dashboard/components-next/Settings/SettingsToggleSection.vue';

const props = defineProps({
  inbox: { type: Object, default: () => ({}) },
  modelValue: { type: Array, default: () => [] },
});

const emit = defineEmits(['update:modelValue']);

const store = useStore();
const getters = useStoreGetters();
const { t } = useI18n();

const limitAttributes = ref(false);
const selectedKeys = ref([]);

const conversationAttributes = computed(() =>
  getters['attributes/getAttributesByModel'].value('conversation_attribute')
);

// Initialize and watch for parent value changes
watch(
  () => props.modelValue,
  (keys) => {
    limitAttributes.value = keys && keys.length > 0;
    selectedKeys.value = [...(keys || [])];
  },
  { immediate: true }
);

store.dispatch('attributes/get');

function toggleAttribute(key) {
  const idx = selectedKeys.value.indexOf(key);
  if (idx === -1) {
    selectedKeys.value.push(key);
  } else {
    selectedKeys.value.splice(idx, 1);
  }
  emit('update:modelValue', [...selectedKeys.value]);
}

watch(limitAttributes, (newVal) => {
  if (!newVal) {
    selectedKeys.value = [];
    emit('update:modelValue', []);
  }
});
</script>

<template>
  <div class="mt-6">
    <h4 class="text-heading-4 text-n-slate-12 mb-2">
      {{ t('INBOX_MGMT.CUSTOM_ATTRIBUTES.SECTION_TITLE') }}
    </h4>
    <SettingsToggleSection
      v-model="limitAttributes"
      :label="t('INBOX_MGMT.CUSTOM_ATTRIBUTES.TITLE')"
      :description="t('INBOX_MGMT.CUSTOM_ATTRIBUTES.DESCRIPTION')"
    />
    <div v-if="limitAttributes" class="mt-4 ml-1">
      <p class="text-sm text-n-slate-11 mb-2">
        {{ t('INBOX_MGMT.CUSTOM_ATTRIBUTES.SELECT_ATTRIBUTES') }}
      </p>
      <div class="flex flex-col gap-2">
        <label
          v-for="attr in conversationAttributes"
          :key="attr.id"
          class="flex items-center gap-2 text-sm"
        >
          <input
            type="checkbox"
            :checked="selectedKeys.includes(attr.attribute_key)"
            @change="toggleAttribute(attr.attribute_key)"
          />
          {{ attr.attribute_display_name }}
        </label>
      </div>
    </div>
  </div>
</template>
