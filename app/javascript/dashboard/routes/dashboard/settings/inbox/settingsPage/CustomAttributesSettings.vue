<script setup>
import { computed, ref, onMounted, watch } from 'vue';
import { useStore, useStoreGetters } from 'dashboard/composables/store';
import { useI18n } from 'vue-i18n';
import SettingsToggleSection from 'dashboard/components-next/Settings/SettingsToggleSection.vue';

const props = defineProps({
  inbox: { type: Object, default: () => ({}) },
});

const store = useStore();
const getters = useStoreGetters();
const { t } = useI18n();

const showAllAttributes = ref(true);
const selectedKeys = ref([]);

const conversationAttributes = computed(() =>
  getters['attributes/getAttributesByModel'].value('conversation_attribute')
);

onMounted(() => {
  store.dispatch('attributes/get');
  const keys = props.inbox.allowed_custom_attribute_keys || [];
  showAllAttributes.value = keys.length === 0;
  selectedKeys.value = [...keys];
});

function toggleAttribute(key) {
  const idx = selectedKeys.value.indexOf(key);
  if (idx === -1) {
    selectedKeys.value.push(key);
  } else {
    selectedKeys.value.splice(idx, 1);
  }
  save();
}

function onToggleAll(value) {
  showAllAttributes.value = value;
  if (value) {
    selectedKeys.value = [];
    save();
  }
}

async function save() {
  const keys = showAllAttributes.value ? [] : selectedKeys.value;
  await store.dispatch('inboxes/updateInbox', {
    id: props.inbox.id,
    allowed_custom_attribute_keys: keys,
  });
}
</script>

<template>
  <div class="mt-6">
    <h4 class="text-heading-4 text-n-slate-12 mb-2">
      {{ t('INBOX_MGMT.CUSTOM_ATTRIBUTES.SECTION_TITLE') }}
    </h4>
    <SettingsToggleSection
      :label="t('INBOX_MGMT.CUSTOM_ATTRIBUTES.TITLE')"
      :description="t('INBOX_MGMT.CUSTOM_ATTRIBUTES.DESCRIPTION')"
      :value="showAllAttributes"
      @input="onToggleAll"
    />
    <div v-if="!showAllAttributes" class="mt-4 ml-1">
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
