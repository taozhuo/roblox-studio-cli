import { useState, useEffect, useCallback } from 'react';
import { invoke } from '@tauri-apps/api/tauri';
import ChatPanel from './components/ChatPanel';
import Sidebar from './components/Sidebar';
import StatusBar from './components/StatusBar';
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

export default function App() {
  const [messages, setMessages] = useState<Message[]>([]);
  const [isLoading, setIsLoading] = useState(false);
  const [editors, setEditors] = useState<EditorConnection[]>([
    { name: 'Roblox Studio', type: 'roblox', connected: false, url: 'http://127.0.0.1:4849' }
  ]);
  const [activeEditor, setActiveEditor] = useState<string>('Roblox Studio');
  const [daemonConnected, setDaemonConnected] = useState(false);
  const [sidebarOpen, setSidebarOpen] = useState(false);

  // Check daemon connection
  useEffect(() => {
    const checkDaemon = async () => {
      try {
        const response = await fetch('http://127.0.0.1:4849/health');
        setDaemonConnected(response.ok);

        // Update Roblox Studio connection status
        if (response.ok) {
          const data = await response.json();
          setEditors(prev => prev.map(e =>
            e.type === 'roblox' ? { ...e, connected: data.pluginConnected || false } : e
          ));
        }
      } catch {
        setDaemonConnected(false);
      }
    };

    checkDaemon();
    const interval = setInterval(checkDaemon, 5000);
    return () => clearInterval(interval);
  }, []);

  const [currentTool, setCurrentTool] = useState<string | null>(null);

  const sendMessage = useCallback(async (content: string) => {
    const userMessage: Message = {
      id: Date.now().toString(),
      role: 'user',
      content,
      timestamp: new Date()
    };

    setMessages(prev => [...prev, userMessage]);
    setIsLoading(true);
    setCurrentTool(null);

    try {
      // Try streaming first, fallback to non-streaming
      const useStreaming = typeof ReadableStream !== 'undefined';
      const endpoint = useStreaming ? 'http://127.0.0.1:4849/chat/stream' : 'http://127.0.0.1:4849/chat';

      const response = await fetch(endpoint, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          message: content,
          history: messages.slice(-10).map(m => ({ role: m.role, content: m.content }))
        })
      });

      if (!response.ok) {
        const errData = await response.json().catch(() => ({}));
        throw new Error(errData.error || `HTTP ${response.status}`);
      }

      // Non-streaming fallback
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
      let fullText = '';
      let assistantMsgId = (Date.now() + 1).toString();

      // Add placeholder assistant message
      setMessages(prev => [...prev, {
        id: assistantMsgId,
        role: 'assistant',
        content: '',
        timestamp: new Date()
      }]);

      while (true) {
        const { done, value } = await reader.read();
        if (done) break;

        const chunk = decoder.decode(value);
        const lines = chunk.split('\n');

        for (const line of lines) {
          if (line.startsWith('data: ')) {
            try {
              const data = JSON.parse(line.slice(6));

              if (data.type === 'text') {
                fullText += data.content;
                setMessages(prev => prev.map(m =>
                  m.id === assistantMsgId ? { ...m, content: fullText } : m
                ));
              } else if (data.type === 'tool_start') {
                setCurrentTool(`🔧 ${data.tool}`);
              } else if (data.type === 'tool_end') {
                setCurrentTool(null);
              } else if (data.type === 'status') {
                setCurrentTool(`⏳ ${data.message}`);
              } else if (data.type === 'error') {
                throw new Error(data.message);
              } else if (data.type === 'done') {
                setCurrentTool(null);
              }
            } catch (e) {
              // Ignore parse errors for incomplete chunks
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
      console.error('Chat error:', error);
      let errorText = 'Unknown error';
      if (error instanceof Error) {
        errorText = error.message;
      }

      const errorMessage: Message = {
        id: (Date.now() + 1).toString(),
        role: 'system',
        content: `Error: ${errorText}`,
        timestamp: new Date()
      };
      setMessages(prev => [...prev, errorMessage]);
    } finally {
      setIsLoading(false);
      setCurrentTool(null);
    }
  }, [messages]);

  const captureViewport = useCallback(async () => {
    try {
      const response = await fetch('http://127.0.0.1:4850/capture');
      if (response.ok) {
        const blob = await response.blob();
        // Could display or process the image
        console.log('Captured viewport:', blob.size, 'bytes');
        return blob;
      }
    } catch (error) {
      console.error('Capture failed:', error);
    }
    return null;
  }, []);

  return (
    <div className="app">
      <Sidebar
        open={sidebarOpen}
        onClose={() => setSidebarOpen(false)}
        editors={editors}
        activeEditor={activeEditor}
        onSelectEditor={setActiveEditor}
      />

      <main className="main-content">
        <ChatPanel
          messages={messages}
          isLoading={isLoading}
          onSendMessage={sendMessage}
          onMenuClick={() => setSidebarOpen(true)}
          onCaptureViewport={captureViewport}
        />
      </main>

      <StatusBar
        daemonConnected={daemonConnected}
        currentTool={currentTool}
        editorConnected={editors.find(e => e.name === activeEditor)?.connected || false}
        activeEditor={activeEditor}
      />
    </div>
  );
}
