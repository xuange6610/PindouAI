import { defineStore } from 'pinia'
import { api } from '../api'
import type { Chat, ChatDetail, FileInfo, Message, ModelInfo } from '../types'

export const useChatStore = defineStore('chat', {
  state: () => ({
    chats: [] as Chat[], models: [] as ModelInfo[], current: null as ChatDetail | null,
    streaming: false, draftAnswer: '',
  }),
  actions: {
    async initialize() {
      const [chats, models] = await Promise.all([api.get<Chat[]>('/chats'), api.get<ModelInfo[]>('/models')])
      this.chats = chats.data
      this.models = models.data
      if (this.chats[0]) await this.open(this.chats[0].id)
    },
    async refreshModels() {
      this.models = (await api.get<ModelInfo[]>('/models')).data
    },
    async open(id: string) {
      this.current = (await api.get<ChatDetail>(`/chats/${id}`)).data
    },
    async create(modelId: string) {
      const chat = (await api.post<Chat>('/chats', { title: '新聊天', model_id: modelId })).data
      this.chats.unshift(chat)
      await this.open(chat.id)
    },
    async remove(id: string) {
      await api.delete(`/chats/${id}`)
      this.chats = this.chats.filter((chat) => chat.id !== id)
      this.current = null
      if (this.chats[0]) await this.open(this.chats[0].id)
    },
    async switchModel(modelId: string) {
      if (!this.current) return
      const updated = (await api.patch<Chat>(`/chats/${this.current.id}`, { model_id: modelId })).data
      this.current = { ...this.current, ...updated }
    },
    async upload(file: File): Promise<FileInfo> {
      const form = new FormData(); form.append('file', file)
      return (await api.post<FileInfo>('/files', form)).data
    },
    async send(content: string, fileIds: string[] = []) {
      if (!this.current || this.streaming) return
      const now = new Date().toISOString()
      this.current.messages.push({ id: crypto.randomUUID(), role: 'user', content, attachments: [], created_at: now })
      this.streaming = true; this.draftAnswer = ''
      try {
        const token = localStorage.getItem('ai-platform-token')
        const response = await fetch(`/api/chats/${this.current.id}/messages/stream`, {
          method: 'POST', headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` },
          body: JSON.stringify({ content, file_ids: fileIds }),
        })
        if (!response.ok || !response.body) {
          const errorBody: any = await response.json().catch(() => null)
          throw new Error(errorBody?.detail ?? `HTTP ${response.status}`)
        }
        const reader = response.body.getReader(); const decoder = new TextDecoder(); let buffer = ''
        while (true) {
          const { value, done } = await reader.read(); if (done) break
          buffer += decoder.decode(value, { stream: true })
          const events = buffer.split('\n\n'); buffer = events.pop() ?? ''
          for (const event of events) {
            const type = event.match(/^event: (.+)$/m)?.[1]
            const raw = event.match(/^data: (.+)$/m)?.[1]
            if (!raw) continue
            const data = JSON.parse(raw)
            if (type === 'delta') this.draftAnswer += data.content
            if (type === 'error') throw new Error(data.detail)
          }
        }
        this.current.messages.push({
          id: crypto.randomUUID(), role: 'assistant', content: this.draftAnswer,
          attachments: [], created_at: new Date().toISOString(),
        })
      } finally {
        this.draftAnswer = ''; this.streaming = false
      }
    },
  },
})
