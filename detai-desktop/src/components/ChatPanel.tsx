import { useState, useRef, useEffect, KeyboardEvent } from 'react';
import type { Message, Session } from '../App';
import MessageBubble from './MessageBubble';
import './ChatPanel.css';

interface ChatPanelProps {
  messages: Message[];
  isLoading: boolean;
  onSendMessage: (content: string) => void;
  onMenuClick: () => void;
  session?: Session | null;
}

export default function ChatPanel({
  messages,
  isLoading,
  onSendMessage,
  onMenuClick,
  session: _session
}: ChatPanelProps) {
  const [input, setInput] = useState('');
  const [isListening, setIsListening] = useState(false);
  const [isFocused, setIsFocused] = useState(false);
  const messagesEndRef = useRef<HTMLDivElement>(null);
  const textareaRef = useRef<HTMLTextAreaElement>(null);

  useEffect(() => {
    messagesEndRef.current?.scrollIntoView({ behavior: 'smooth' });
  }, [messages]);

  useEffect(() => {
    if (textareaRef.current) {
      textareaRef.current.style.height = 'auto';
      textareaRef.current.style.height = Math.min(textareaRef.current.scrollHeight, 160) + 'px';
    }
  }, [input]);

  const handleSend = () => {
    if (!input.trim() || isLoading) return;
    onSendMessage(input.trim());
    setInput('');
  };

  const handleKeyDown = (e: KeyboardEvent<HTMLTextAreaElement>) => {
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault();
      handleSend();
    }
  };

  const toggleSpeech = async () => {
    try {
      if (isListening) {
        await fetch('http://127.0.0.1:4850/speech/stop', { method: 'POST' });
        const response = await fetch('http://127.0.0.1:4850/speech/transcription');
        if (response.ok) {
          const data = await response.json();
          if (data.text) {
            setInput(prev => prev + (prev ? ' ' : '') + data.text);
          }
        }
        setIsListening(false);
      } else {
        const response = await fetch('http://127.0.0.1:4850/speech/listen', { method: 'POST' });
        if (response.ok) {
          setIsListening(true);
        }
      }
    } catch (error) {
      console.error('Speech error:', error);
      setIsListening(false);
    }
  };

  return (
    <div className="chat-panel">
      {/* Header */}
      <header className="chat-header">
        <div className="header-left">
          <button className="header-btn" onClick={onMenuClick} aria-label="Menu">
            <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
              <line x1="4" y1="6" x2="20" y2="6" />
              <line x1="4" y1="12" x2="20" y2="12" />
              <line x1="4" y1="18" x2="20" y2="18" />
            </svg>
          </button>
        </div>

        <div className="header-center">
          <div className="logo-mark">
            <svg width="22" height="22" viewBox="0 0 32 32" fill="none">
              <defs>
                <linearGradient id="logo-gradient" x1="0%" y1="0%" x2="100%" y2="100%">
                  <stop offset="0%" stopColor="#818cf8" />
                  <stop offset="100%" stopColor="#6366f1" />
                </linearGradient>
              </defs>
              <path d="M16 3L28 9.5V22.5L16 29L4 22.5V9.5L16 3Z" fill="url(#logo-gradient)" />
              <path d="M16 10L22 13.5V20.5L16 24L10 20.5V13.5L16 10Z" fill="#0c0c0d" fillOpacity="0.4" />
            </svg>
          </div>
          <span className="header-title">Bakable</span>
        </div>

        <div className="header-right">
          {/* Placeholder for future actions */}
        </div>
      </header>

      {/* Messages */}
      <div className="messages-container">
        {messages.length === 0 ? (
          <div className="empty-state">
            <div className="empty-icon">
              <div className="empty-icon-inner">
                <svg width="32" height="32" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
                  <path d="M21 11.5a8.38 8.38 0 0 1-.9 3.8 8.5 8.5 0 0 1-7.6 4.7 8.38 8.38 0 0 1-3.8-.9L3 21l1.9-5.7a8.38 8.38 0 0 1-.9-3.8 8.5 8.5 0 0 1 4.7-7.6 8.38 8.38 0 0 1 3.8-.9h.5a8.48 8.48 0 0 1 8 8v.5z" />
                </svg>
              </div>
            </div>
            <h2 className="empty-title">Start a conversation</h2>
            <p className="empty-description">
              Ask me to help build your game — write scripts, fix bugs, design systems, or modify your scene.
            </p>
            <div className="empty-suggestions">
              <button className="suggestion-chip" onClick={() => setInput('Create a player movement script')}>
                Create a movement script
              </button>
              <button className="suggestion-chip" onClick={() => setInput('Fix the bug in my code')}>
                Debug my code
              </button>
              <button className="suggestion-chip" onClick={() => setInput('Explain how raycasting works')}>
                Explain raycasting
              </button>
            </div>
          </div>
        ) : (
          <div className="messages-list">
            {messages.map((message, index) => (
              <MessageBubble
                key={message.id}
                message={message}
                isLast={index === messages.length - 1}
              />
            ))}
            {isLoading && (
              <div className="typing-indicator">
                <div className="typing-avatar">
                  <svg width="16" height="16" viewBox="0 0 32 32" fill="none">
                    <path d="M16 3L28 9.5V22.5L16 29L4 22.5V9.5L16 3Z" fill="url(#logo-gradient)" />
                  </svg>
                </div>
                <div className="typing-dots">
                  <span />
                  <span />
                  <span />
                </div>
              </div>
            )}
            <div ref={messagesEndRef} />
          </div>
        )}
      </div>

      {/* Input */}
      <div className="input-container">
        <div className={`input-wrapper ${isFocused ? 'focused' : ''} ${input.trim() ? 'has-content' : ''}`}>
          <textarea
            ref={textareaRef}
            value={input}
            onChange={e => setInput(e.target.value)}
            onKeyDown={handleKeyDown}
            onFocus={() => setIsFocused(true)}
            onBlur={() => setIsFocused(false)}
            placeholder="Message Bakable..."
            rows={1}
            disabled={isLoading}
          />
          <div className="input-actions">
            <button
              className={`action-btn mic-btn ${isListening ? 'active' : ''}`}
              onClick={toggleSpeech}
              aria-label={isListening ? 'Stop listening' : 'Voice input'}
            >
              {isListening ? (
                <div className="mic-waves">
                  <span /><span /><span />
                </div>
              ) : (
                <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                  <path d="M12 1a3 3 0 0 0-3 3v8a3 3 0 0 0 6 0V4a3 3 0 0 0-3-3z" />
                  <path d="M19 10v2a7 7 0 0 1-14 0v-2" />
                  <line x1="12" y1="19" x2="12" y2="23" />
                  <line x1="8" y1="23" x2="16" y2="23" />
                </svg>
              )}
            </button>
            <button
              className={`action-btn send-btn ${input.trim() && !isLoading ? 'active' : ''}`}
              onClick={handleSend}
              disabled={!input.trim() || isLoading}
              aria-label="Send message"
            >
              <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                <line x1="22" y1="2" x2="11" y2="13" />
                <polygon points="22 2 15 22 11 13 2 9 22 2" />
              </svg>
            </button>
          </div>
        </div>
        <p className="input-hint">
          <kbd>Enter</kbd> to send · <kbd>Shift + Enter</kbd> for new line
        </p>
      </div>
    </div>
  );
}
