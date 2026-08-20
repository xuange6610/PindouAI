<script setup lang="ts">
import { Delete, EditPen, Plus } from '@element-plus/icons-vue'
import { ElMessage } from 'element-plus'
import { useChatStore } from '../stores/chat'

const chat = useChatStore()
async function create() {
  if (!chat.models[0]) return ElMessage.warning('请先在模型管理中添加模型')
  await chat.create(chat.models[0].id)
}
</script>

<template>
  <aside class="flex h-full w-[272px] shrink-0 flex-col border-r border-[#d8dfdc] bg-[#f7f9f8]">
    <div class="flex h-16 items-center gap-3 px-4"><div class="grid h-9 w-9 place-items-center bg-[#16776d] font-bold text-white">AI</div><strong>多模型工作台</strong></div>
    <div class="px-3 pb-3"><el-button :icon="Plus" class="w-full" @click="create">新聊天</el-button></div>
    <div class="min-h-0 flex-1 overflow-y-auto px-2">
      <button v-for="item in chat.chats" :key="item.id" class="group mb-1 flex w-full items-center gap-2 border-0 px-3 py-2.5 text-left" :class="item.id === chat.current?.id ? 'bg-[#dcebe7]' : 'bg-transparent hover:bg-[#e9efed]'" @click="chat.open(item.id)">
        <el-icon><EditPen /></el-icon><span class="min-w-0 flex-1 truncate text-sm">{{ item.title }}</span>
        <el-button text circle :icon="Delete" class="opacity-0 group-hover:opacity-100" @click.stop="chat.remove(item.id)" />
      </button>
    </div>
  </aside>
</template>
