import { defineStore } from 'pinia'
import { api } from '../api'
import type { User } from '../types'

export const useAuthStore = defineStore('auth', {
  state: () => ({ user: null as User | null }),
  actions: {
    async login(identifier: string, password: string) {
      const body = new URLSearchParams({ username: identifier, password })
      const { data } = await api.post('/auth/login', body, {
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      })
      localStorage.setItem('ai-platform-token', data.access_token)
      this.user = data.user
    },
    async register(email: string, password: string, displayName: string) {
      const { data } = await api.post('/auth/register', {
        email, password, display_name: displayName,
      })
      localStorage.setItem('ai-platform-token', data.access_token)
      this.user = data.user
    },
    async load() {
      const { data } = await api.get<User>('/auth/me')
      this.user = data
    },
    logout() {
      localStorage.removeItem('ai-platform-token')
      this.user = null
      location.assign('/login')
    },
  },
})
