<script setup lang="ts">
import { computed } from 'vue'
import { useChatStore } from '../stores/chat'

const chat = useChatStore()
const selected = computed({ get: () => chat.current?.model_id ?? '', set: (value) => chat.switchModel(value) })
</script>

<template>
  <el-select v-model="selected" filterable placeholder="选择模型" class="w-[260px]" :disabled="!chat.current">
    <el-option v-for="model in chat.models" :key="model.id" :value="model.id" :label="`${model.name} · ${model.provider}`">
      <div class="flex justify-between gap-5"><span>{{ model.name }}</span><span class="text-xs text-[#70807c]">{{ model.model_id }}</span></div>
    </el-option>
  </el-select>
</template>
