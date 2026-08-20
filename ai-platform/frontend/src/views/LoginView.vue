<script setup lang="ts">
import { ref } from 'vue'
import { useRouter } from 'vue-router'
import { ElMessage } from 'element-plus'
import { useAuthStore } from '../stores/auth'

const auth = useAuthStore(); const router = useRouter()
const mode = ref<'login' | 'register'>('login')
const email = ref(''); const password = ref(''); const displayName = ref('')
const loading = ref(false)

async function submit() {
  loading.value = true
  try {
    if (mode.value === 'login') await auth.login(email.value, password.value)
    else await auth.register(email.value, password.value, displayName.value)
    await router.replace('/')
  } catch (error: any) {
    ElMessage.error(error.response?.data?.detail ?? error.message ?? '操作失败')
  } finally { loading.value = false }
}
</script>

<template>
  <main class="grid min-h-full place-items-center bg-[#eef2f1] p-5">
    <section class="w-full max-w-[420px] border border-[#d8dfdc] bg-white p-8 shadow-sm">
      <div class="mb-7 flex items-center gap-3">
        <div class="grid h-11 w-11 place-items-center bg-[#16776d] text-lg font-bold text-white">AI</div>
        <div><h1 class="m-0 text-xl font-bold">AI 多模型工作台</h1><p class="m-0 mt-1 text-sm text-[#65716e]">统一、安全地使用你的模型 API</p></div>
      </div>
      <el-segmented v-model="mode" :options="[{ label: '登录', value: 'login' }, { label: '注册', value: 'register' }]" class="mb-6 w-full" />
      <el-form label-position="top" @submit.prevent="submit">
        <el-form-item v-if="mode === 'register'" label="显示名称"><el-input v-model="displayName" autocomplete="name" /></el-form-item>
        <el-form-item label="邮箱或手机号"><el-input v-model="email" autocomplete="username" /></el-form-item>
        <el-form-item label="密码"><el-input v-model="password" type="password" show-password autocomplete="current-password" @keyup.enter="submit" /></el-form-item>
        <el-button type="primary" native-type="submit" :loading="loading" class="mt-2 w-full">{{ mode === 'login' ? '登录' : '创建账号' }}</el-button>
      </el-form>
    </section>
  </main>
</template>
