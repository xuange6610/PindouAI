<script setup lang="ts">
import { reactive, ref } from 'vue'
import { ElMessage } from 'element-plus'
import { api } from '../api'
import { useChatStore } from '../stores/chat'

defineProps<{ modelValue: boolean }>()
const emit = defineEmits<{ 'update:modelValue': [value: boolean] }>()
const chat = useChatStore(); const saving = ref(false)
const form = reactive({
  name: '', provider: 'openai', api_base: 'https://api.openai.com/v1', api_key: '',
  model_id: '', model_type: 'chat', max_tokens: 8192, input_price: 0, output_price: 0,
  capabilities: { vision: false, files: false, tools: false },
})
async function save() {
  saving.value = true
  try {
    await api.post('/models', form)
    await chat.refreshModels(); form.api_key = ''; form.name = ''; form.model_id = ''
    ElMessage.success('模型已添加，API Key 已加密保存')
  } catch (error: any) { ElMessage.error(error.response?.data?.detail ?? '添加失败') } finally { saving.value = false }
}
async function remove(id: string) {
  await api.delete(`/models/${id}`); await chat.refreshModels(); ElMessage.success('模型已停用')
}
</script>

<template>
  <el-drawer :model-value="modelValue" title="模型管理" size="min(620px, 92vw)" @update:model-value="emit('update:modelValue', $event)">
    <el-form label-position="top" @submit.prevent="save">
      <div class="grid grid-cols-1 gap-x-4 sm:grid-cols-2">
        <el-form-item label="显示名称"><el-input v-model="form.name" placeholder="例如 GPT-5" /></el-form-item>
        <el-form-item label="Provider 协议"><el-select v-model="form.provider" class="w-full"><el-option v-for="value in ['openai','anthropic','qwen','glm','kimi','deepseek','ollama','vllm','openrouter']" :key="value" :label="value" :value="value" /></el-select></el-form-item>
      </div>
      <el-form-item label="API 地址"><el-input v-model="form.api_base" placeholder="https://.../v1" /></el-form-item>
      <el-form-item label="API Key"><el-input v-model="form.api_key" type="password" show-password autocomplete="off" /></el-form-item>
      <div class="grid grid-cols-1 gap-x-4 sm:grid-cols-2"><el-form-item label="模型 ID"><el-input v-model="form.model_id" placeholder="网关实际模型名称" /></el-form-item><el-form-item label="最大 Token"><el-input-number v-model="form.max_tokens" :min="1" :max="10000000" class="w-full" /></el-form-item></div>
      <div class="mb-5 flex flex-wrap gap-5"><el-checkbox v-model="form.capabilities.vision">图片理解</el-checkbox><el-checkbox v-model="form.capabilities.files">文件输入</el-checkbox><el-checkbox v-model="form.capabilities.tools">工具调用</el-checkbox></div>
      <el-button type="primary" native-type="submit" :loading="saving">保存模型</el-button>
    </el-form>
    <el-divider />
    <el-table :data="chat.models" empty-text="还没有模型"><el-table-column prop="name" label="名称" /><el-table-column prop="provider" label="Provider" width="110" /><el-table-column prop="model_id" label="模型 ID" /><el-table-column label="操作" width="80"><template #default="scope"><el-button type="danger" link @click="remove(scope.row.id)">停用</el-button></template></el-table-column></el-table>
  </el-drawer>
</template>
