import { createRouter, createWebHistory } from 'vue-router'
import LoginView from './views/LoginView.vue'
import ChatView from './views/ChatView.vue'

const router = createRouter({
  history: createWebHistory(),
  routes: [
    { path: '/login', component: LoginView },
    { path: '/', component: ChatView, meta: { auth: true } },
  ],
})

router.beforeEach((to) => {
  const token = localStorage.getItem('ai-platform-token')
  if (to.meta.auth && !token) return '/login'
  if (to.path === '/login' && token) return '/'
})

export default router
