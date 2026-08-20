<script setup lang="ts">
import { ref } from 'vue'
import { DocumentAdd, Microphone, Promotion } from '@element-plus/icons-vue'
import { ElMessage } from 'element-plus'
import { useChatStore } from '../stores/chat'
import type { FileInfo } from '../types'

const chat = useChatStore(); const text = ref(''); const attachment = ref<FileInfo | null>(null); const uploading = ref(false)
async function choose(event: Event) {
  const input = event.target as HTMLInputElement; const file = input.files?.[0]; input.value = ''
  if (!file) return
  uploading.value = true
  try { attachment.value = await chat.upload(file) } catch (error: any) { ElMessage.error(error.response?.data?.detail ?? '上传失败') } finally { uploading.value = false }
}
async function send() {
  const content = text.value.trim(); if (!content || chat.streaming) return
  text.value = ''
  const fileIds = attachment.value ? [attachment.value.id] : []; attachment.value = null
  try { await chat.send(content, fileIds) } catch (error: any) { ElMessage.error(error.message ?? '模型调用失败') }
}
</script>

<template>
  <div class="mx-auto w-full max-w-[900px] px-5 pb-5">
    <div v-if="attachment" class="mb-2 inline-flex items-center gap-2 border border-[#cad5d1] bg-white px-3 py-1.5 text-sm"><el-icon><DocumentAdd /></el-icon><span class="max-w-[320px] truncate">{{ attachment.original_name }}</span><button class="border-0 bg-transparent" @click="attachment = null">×</button></div>
    <div class="flex items-end gap-2 border border-[#bac8c4] bg-white p-2 shadow-sm focus-within:border-[#16776d]">
      <label class="grid h-9 w-9 cursor-pointer place-items-center hover:bg-[#edf2f0]" title="上传文件"><el-icon><DocumentAdd /></el-icon><input type="file" class="hidden" :disabled="uploading" @change="choose" /></label>
      <textarea v-model="text" rows="1" class="max-h-44 min-h-9 flex-1 resize-none border-0 px-2 py-2 outline-none" placeholder="输入消息，Shift+Enter 换行" @keydown.enter.exact.prevent="send" />
      <el-button text circle :icon="Microphone" title="语音输入" disabled />
      <el-button type="primary" circle :icon="Promotion" :loading="chat.streaming" @click="send" />
    </div>
    <p class="m-0 mt-2 text-center text-xs text-[#77827f]">回答可能不准确，重要信息请核实</p>
  </div>
</template>
