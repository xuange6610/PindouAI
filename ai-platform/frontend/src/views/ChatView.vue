<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { Setting, SwitchButton } from '@element-plus/icons-vue'
import { ElMessage } from 'element-plus'
import { useAuthStore } from '../stores/auth'
import { useChatStore } from '../stores/chat'
import ChatSidebar from '../components/ChatSidebar.vue'
import ModelSelector from '../components/ModelSelector.vue'
import MessageItem from '../components/MessageItem.vue'
import ChatComposer from '../components/ChatComposer.vue'
import ModelManagement from '../components/ModelManagement.vue'

const auth = useAuthStore(); const chat = useChatStore()
const settingsOpen = ref(false)
const draft = computed(() => ({ id: 'draft', role: 'assistant', content: chat.draftAnswer, attachments: [], created_at: new Date().toISOString() }))
onMounted(async () => {
  try { await Promise.all([auth.load(), chat.initialize()]) } catch (error: any) { ElMessage.error(error.response?.data?.detail ?? '初始化失败') }
})
</script>

<template>
  <main class="flex h-full min-w-0 bg-white">
    <ChatSidebar class="hidden md:flex" />
    <section class="flex min-w-0 flex-1 flex-col">
      <header class="flex h-16 shrink-0 items-center justify-between border-b border-[#d8dfdc] px-4 md:px-6">
        <ModelSelector />
        <div class="flex items-center gap-1"><span class="mr-2 hidden text-sm text-[#5f6c68] sm:block">{{ auth.user?.display_name }}</span><el-button text circle :icon="Setting" title="模型设置" @click="settingsOpen = true" /><el-button text circle :icon="SwitchButton" title="退出" @click="auth.logout" /></div>
      </header>
      <div v-if="chat.current" class="min-h-0 flex-1 overflow-y-auto">
        <MessageItem v-for="message in chat.current.messages" :key="message.id" :message="message" />
        <MessageItem v-if="chat.draftAnswer" :message="draft" />
      </div>
      <div v-else class="grid min-h-0 flex-1 place-items-center p-8 text-center"><div><h1 class="text-2xl font-bold">选择模型并新建聊天</h1><p class="text-[#65716e]">你的 API Key 仅在服务器加密保存，浏览器不会直接调用模型。</p></div></div>
      <ChatComposer />
    </section>
    <ModelManagement v-model="settingsOpen" />
  </main>
</template>
