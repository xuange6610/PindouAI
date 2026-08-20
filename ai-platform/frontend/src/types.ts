export interface User { id: string; email: string; display_name: string; role: 'admin' | 'user' | 'guest' }
export interface ModelInfo { id: string; name: string; model_id: string; provider: string; model_type: string; capabilities: Record<string, unknown> }
export interface Chat { id: string; title: string; model_id: string | null; created_at: string; updated_at: string }
export interface Message { id: string; role: string; content: string; attachments: Array<Record<string, unknown>>; created_at: string }
export interface ChatDetail extends Chat { messages: Message[] }
export interface FileInfo { id: string; original_name: string; mime_type: string; size_bytes: number; status: string }
