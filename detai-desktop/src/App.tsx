import { useState, useEffect, useCallback, useRef } from 'react';
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

export interface Session {
  placeId: number;
  gameId: number;
  placeName: string;
  isPublished: boolean;
  sessionKey: string;
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
      const useStreaming = typeof ReadableStream !== 'undefined';
      const endpoint = useStreaming ? 'http://127.0.0.1:4849/chat/stream' : 'http://127.0.0.1:4849/chat';

      const response = await fetch(endpoint, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          message: content,
          sessionId: claudeSessionId // Resume session if we have one
        })
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
      let fullText = '';
      let assistantMsgId = (Date.now() + 1).toString();

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
                setCurrentTool(data.tool);
              } else if (data.type === 'tool_end') {
                setCurrentTool(null);
              } else if (data.type === 'status') {
                setCurrentTool(data.message);
              } else if (data.type === 'session') {
                // Capture session ID for conversation continuity
                setClaudeSessionId(data.sessionId);
                console.log('Session ID:', data.sessionId);
              } else if (data.type === 'error') {
                throw new Error(data.message);
              } else if (data.type === 'done') {
                setCurrentTool(null);
              }
            } catch (e) {
              // Ignore parse errors
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
      const errorMessage: Message = {
        id: (Date.now() + 1).toString(),
        role: 'system',
        content: `Error: ${error instanceof Error ? error.message : 'Unknown error'}`,
        timestamp: new Date()
      };
      setMessages(prev => [...prev, errorMessage]);
    } finally {
      setIsLoading(false);
      setCurrentTool(null);
    }
  }, [claudeSessionId]);

  const clearChat = useCallback(() => {
    setMessages([]);
    setClaudeSessionId(null); // Start fresh session
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
      />

      <main className="main-content">
        <ChatPanel
          messages={messages}
          isLoading={isLoading}
          onSendMessage={sendMessage}
          onMenuClick={() => setSidebarOpen(true)}
          session={session}
        />
      </main>

      <StatusBar
        daemonConnected={daemonConnected}
        currentTool={currentTool}
        editorConnected={editors.find(e => e.name === activeEditor)?.connected || false}
        activeEditor={activeEditor}
        session={session}
      />
    </div>
  );
}
