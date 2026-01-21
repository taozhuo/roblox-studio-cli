import { useState, useEffect, useCallback, useRef } from 'react';
import ChatPanel, { ImageAttachment } from './components/ChatPanel';
import Sidebar from './components/Sidebar';
import StatusBar from './components/StatusBar';
import TodoPanel from './components/TodoPanel';
import './App.css';

export interface Message {
  id: string;
  role: 'user' | 'assistant' | 'system';
  content: string;
  timestamp: Date;
}

export interface EditorConnection {
  name: string;
  type: 'roblox' | 'godot' | 'unity' | 'generic';
  connected: boolean;
  url?: string;
}

export interface Session {
  placeId: number;
  gameId: number;
  placeName: string;
  isPublished: boolean;
  sessionKey: string;
}

export interface TodoItem {
  content: string;
  status: 'pending' | 'in_progress' | 'completed';
  activeForm?: string;
}


export default function App() {
  const [messages, setMessages] = useState<Message[]>([]);
  const [isLoading, setIsLoading] = useState(false);
  const [editors, setEditors] = useState<EditorConnection[]>([
    { name: 'Roblox Studio', type: 'roblox', connected: false, url: 'http://127.0.0.1:4849' }
  ]);
  const [activeEditor, setActiveEditor] = useState<string>('Roblox Studio');
  const [daemonConnected, setDaemonConnected] = useState(false);
  const [sidebarOpen, setSidebarOpen] = useState(false);
  const [currentTool, setCurrentTool] = useState<string | null>(null);
  const [session, setSession] = useState<Session | null>(null);
  const lastSessionKey = useRef<string | null>(null);
  const [claudeSessionId, setClaudeSessionId] = useState<string | null>(null);
  const toolClearTimeout = useRef<ReturnType<typeof setTimeout> | null>(null);
  const abortControllerRef = useRef<AbortController | null>(null);
  const [yoloMode, setYoloMode] = useState(() => {
    // Load from localStorage, default to true (YOLO)
    const saved = localStorage.getItem('bakable-yolo-mode');
    return saved !== null ? saved === 'true' : true;
  });
  const [todos, setTodos] = useState<TodoItem[]>([]);
  const [showTodos, setShowTodos] = useState(true); // Auto-show when todos arrive

  // Save yoloMode to localStorage when it changes
  useEffect(() => {
    localStorage.setItem('bakable-yolo-mode', String(yoloMode));
  }, [yoloMode]);

  // Check daemon connection and session
  useEffect(() => {
    const checkDaemon = async () => {
      try {
        const response = await fetch('http://127.0.0.1:4849/health');
        setDaemonConnected(response.ok);

        if (response.ok) {
          const data = await response.json();
          setEditors(prev => prev.map(e =>
            e.type === 'roblox' ? { ...e, connected: data.pluginConnected || false } : e
          ));

          // Track session
          if (data.session) {
            const newSession = data.session as Session;
            setSession(newSession);

            // Check if session changed
            if (lastSessionKey.current && lastSessionKey.current !== newSession.sessionKey) {
              // Session changed - add system message
              setMessages(prev => [...prev, {
                id: Date.now().toString(),
                role: 'system',
                content: `Switched to: ${newSession.placeName}${newSession.isPublished ? ` (ID: ${newSession.placeId})` : ' (unpublished)'}`,
                timestamp: new Date()
              }]);
            }
            lastSessionKey.current = newSession.sessionKey;
          } else {
            setSession(null);
          }
        }
      } catch {
        setDaemonConnected(false);
        setSession(null);
      }
    };

    checkDaemon();
    const interval = setInterval(checkDaemon, 3000);
    return () => clearInterval(interval);
  }, []);

  const cancelRequest = useCallback(() => {
    if (abortControllerRef.current) {
      abortControllerRef.current.abort();
      abortControllerRef.current = null;
    }
    setIsLoading(false);
    setCurrentTool(null);
  }, []);

  const sendMessage = useCallback(async (content: string, images?: ImageAttachment[]) => {
    // Cancel any existing request
    if (abortControllerRef.current) {
      abortControllerRef.current.abort();
    }

    const userMessage: Message = {
      id: Date.now().toString(),
      role: 'user',
      content: images?.length ? `${content} [${images.length} image(s) attached]` : content,
      timestamp: new Date()
    };

    setMessages(prev => [...prev, userMessage]);
    setIsLoading(true);
    setCurrentTool(null);

    // Create new abort controller for this request
    const abortController = new AbortController();
    abortControllerRef.current = abortController;

    let fullText = ''; // Declare outside try so catch can access it

    try {
      const useStreaming = typeof ReadableStream !== 'undefined';
      const endpoint = useStreaming ? 'http://127.0.0.1:4849/chat/stream' : 'http://127.0.0.1:4849/chat';

      // No timeout - AI can take a long time with tool calls
      const response = await fetch(endpoint, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          message: content,
          images: images, // Base64 images for Claude vision
          sessionId: claudeSessionId, // Resume session if we have one
          yoloMode // YOLO = bypass permissions, false = ask for each action
        }),
        signal: abortController.signal
      });

      if (!response.ok) {
        const errData = await response.json().catch(() => ({}));
        throw new Error(errData.error || `HTTP ${response.status}`);
      }

      if (!useStreaming || !response.body) {
        const data = await response.json();
        setMessages(prev => [...prev, {
          id: (Date.now() + 1).toString(),
          role: 'assistant',
          content: data.response || 'No response',
          timestamp: new Date()
        }]);
        return;
      }

      const reader = response.body.getReader();
      const decoder = new TextDecoder();
      fullText = ''; // Reset for streaming
      let assistantMsgId = (Date.now() + 1).toString();
      let buffer = ''; // Buffer for partial SSE messages

      setMessages(prev => [...prev, {
        id: assistantMsgId,
        role: 'assistant',
        content: '',
        timestamp: new Date()
      }]);

      while (true) {
        const { done, value } = await reader.read();
        if (done) break;

        // Append new chunk to buffer
        buffer += decoder.decode(value, { stream: true });

        // Process complete messages (split by double newline)
        const messages = buffer.split('\n\n');
        // Keep last incomplete message in buffer
        buffer = messages.pop() || '';

        for (const msg of messages) {
          const lines = msg.split('\n');
          for (const line of lines) {
            if (line.startsWith('data: ')) {
              try {
                const data = JSON.parse(line.slice(6));
                console.log('[SSE]', data.type, data); // Debug logging

                if (data.type === 'text') {
                  fullText += data.content;
                  setMessages(prev => prev.map(m =>
                    m.id === assistantMsgId ? { ...m, content: fullText } : m
                  ));
                } else if (data.type === 'tool_start') {
                  console.log('[SSE] Tool started:', data.tool);
                  if (toolClearTimeout.current) {
                    clearTimeout(toolClearTimeout.current);
                    toolClearTimeout.current = null;
                  }
                  setCurrentTool(data.tool);
                } else if (data.type === 'tool_end') {
                  console.log('[SSE] Tool ended');
                  toolClearTimeout.current = setTimeout(() => {
                    setCurrentTool(null);
                    toolClearTimeout.current = null;
                  }, 500);
                } else if (data.type === 'status') {
                  if (toolClearTimeout.current) {
                    clearTimeout(toolClearTimeout.current);
                    toolClearTimeout.current = null;
                  }
                  setCurrentTool(data.message);
                } else if (data.type === 'session') {
                  // Capture session ID for conversation continuity
                  setClaudeSessionId(data.sessionId);
                  console.log('Session ID:', data.sessionId);
                } else if (data.type === 'todos') {
                  // Update todos from TodoWrite tool
                  console.log('[SSE] Todos received:', data.todos.length);
                  setTodos(data.todos);
                  setShowTodos(true); // Auto-show when todos update
                } else if (data.type === 'error') {
                  throw new Error(data.message);
                } else if (data.type === 'done') {
                  setCurrentTool(null);
                }
              } catch (e) {
                // Re-throw actual errors (not parse errors)
                if (e instanceof Error && !e.message.includes('JSON')) {
                  throw e;
                }
                console.warn('[SSE] Parse error:', e, line);
              }
            }
          }
        }
      }

      if (!fullText) {
        setMessages(prev => prev.map(m =>
          m.id === assistantMsgId ? { ...m, content: 'No response generated' } : m
        ));
      }

    } catch (error) {
      // Handle abort errors gracefully
      if (error instanceof Error && error.name === 'AbortError') {
        console.log('Request was cancelled');
        return;
      }

      console.error('Chat error:', error);
      console.error('Error type:', error?.constructor?.name);
      console.error('Error stack:', error instanceof Error ? error.stack : 'no stack');

      // If we already have content, just use it (ignore "Load failed" type errors)
      if (fullText && fullText.length > 0) {
        console.log('Stream ended with error but we have content, using it:', fullText.length, 'chars');
        // Content already displayed via streaming updates, just return
        return;
      }

      const errorMessage: Message = {
        id: (Date.now() + 1).toString(),
        role: 'system',
        content: `Error: ${error instanceof Error ? error.message : 'Unknown error'}`,
        timestamp: new Date()
      };
      setMessages(prev => [...prev, errorMessage]);
    } finally {
      abortControllerRef.current = null;
      setIsLoading(false);
      setCurrentTool(null);
    }
  }, [claudeSessionId, yoloMode]);

  const clearChat = useCallback(() => {
    setMessages([]);
    setClaudeSessionId(null); // Start fresh session
    setTodos([]); // Clear todos
  }, []);

  return (
    <div className="app">
      <Sidebar
        open={sidebarOpen}
        onClose={() => setSidebarOpen(false)}
        editors={editors}
        activeEditor={activeEditor}
        onSelectEditor={setActiveEditor}
        onClearChat={clearChat}
        yoloMode={yoloMode}
        onToggleYolo={() => setYoloMode(!yoloMode)}
      />

      <main className="main-content">
        <ChatPanel
          messages={messages}
          isLoading={isLoading}
          onSendMessage={sendMessage}
          onCancel={cancelRequest}
          onMenuClick={() => setSidebarOpen(true)}
          session={session}
          currentTool={currentTool}
          yoloMode={yoloMode}
          onToggleYolo={() => setYoloMode(!yoloMode)}
        />
      </main>

      <StatusBar
        daemonConnected={daemonConnected}
        editorConnected={editors.find(e => e.name === activeEditor)?.connected || false}
        activeEditor={activeEditor}
        session={session}
      />

      {showTodos && todos.length > 0 && (
        <TodoPanel
          todos={todos}
          onClose={() => setShowTodos(false)}
        />
      )}
    </div>
  );
}
