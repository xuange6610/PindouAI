<script setup lang="ts">
import { computed } from 'vue'
import MarkdownIt from 'markdown-it'
import DOMPurify from 'dompurify'
import hljs from 'highlight.js'
import type { Message } from '../types'

const props = defineProps<{ message: Message }>()
const markdown = new MarkdownIt({
  html: false, linkify: true, breaks: true,
  highlight(code, language) {
    if (language && hljs.getLanguage(language)) return hljs.highlight(code, { language }).value
    return hljs.highlightAuto(code).value
  },
})
const rendered = computed(() => DOMPurify.sanitize(markdown.render(props.message.content)))
</script>

<template>
  <article class="border-b border-[#e1e6e4] py-7" :class="message.role === 'user' ? 'bg-white' : 'bg-[#f8faf9]'">
    <div class="mx-auto flex max-w-[860px] gap-4 px-6">
      <div class="grid h-8 w-8 shrink-0 place-items-center text-xs font-bold text-white" :class="message.role === 'user' ? 'bg-[#344744]' : 'bg-[#16776d]'">{{ message.role === 'user' ? '你' : 'AI' }}</div>
      <div class="markdown-body min-w-0 flex-1" v-html="rendered" />
    </div>
  </article>
</template>
