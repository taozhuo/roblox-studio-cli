import { useState, useRef, useEffect, KeyboardEvent } from 'react';
import type { Message, Session } from '../App';
import MessageBubble from './MessageBubble';
import './ChatPanel.css';

export interface ImageAttachment {
  type: 'base64';
  media_type: 'image/png' | 'image/jpeg' | 'image/gif' | 'image/webp';
  data: string;
  name?: string;
}

interface ChatPanelProps {
  messages: Message[];
  isLoading: boolean;
  onSendMessage: (content: string, images?: ImageAttachment[]) => void;
  onCancel: () => void;
  onMenuClick: () => void;
  session?: Session | null;
  currentTool?: string | null;
  yoloMode: boolean;
  onToggleYolo: () => void;
}

export default function ChatPanel({
  messages,
  isLoading,
  onSendMessage,
  onCancel,
  onMenuClick,
  session: _session,
  currentTool,
  yoloMode,
  onToggleYolo
}: ChatPanelProps) {
  const [input, setInput] = useState('');
  const [isListening, setIsListening] = useState(false);
  const [isFocused, setIsFocused] = useState(false);
  const [showModeMenu, setShowModeMenu] = useState(false);
  const [showAttachMenu, setShowAttachMenu] = useState(false);
  const [pendingImages, setPendingImages] = useState<ImageAttachment[]>([]);
  const messagesEndRef = useRef<HTMLDivElement>(null);
  const textareaRef = useRef<HTMLTextAreaElement>(null);
  const modeMenuRef = useRef<HTMLDivElement>(null);
  const attachMenuRef = useRef<HTMLDivElement>(null);
  const fileInputRef = useRef<HTMLInputElement>(null);

  useEffect(() => {
    messagesEndRef.current?.scrollIntoView({ behavior: 'smooth' });
  }, [messages]);

  useEffect(() => {
    if (textareaRef.current) {
      textareaRef.current.style.height = 'auto';
      textareaRef.current.style.height = Math.min(textareaRef.current.scrollHeight, 160) + 'px';
    }
  }, [input]);

  // Close menus when clicking outside
  useEffect(() => {
    const handleClickOutside = (e: MouseEvent) => {
      if (modeMenuRef.current && !modeMenuRef.current.contains(e.target as Node)) {
        setShowModeMenu(false);
      }
      if (attachMenuRef.current && !attachMenuRef.current.contains(e.target as Node)) {
        setShowAttachMenu(false);
      }
    };
    if (showModeMenu || showAttachMenu) {
      document.addEventListener('mousedown', handleClickOutside);
      return () => document.removeEventListener('mousedown', handleClickOutside);
    }
  }, [showModeMenu, showAttachMenu]);

  const handleSend = () => {
    if (!input.trim() && pendingImages.length === 0) return;
    onSendMessage(input.trim(), pendingImages.length > 0 ? pendingImages : undefined);
    setInput('');
    setPendingImages([]);
  };

  const handleKeyDown = (e: KeyboardEvent<HTMLTextAreaElement>) => {
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault();
      handleSend();
    }
  };

  const takeScreenshot = async () => {
    setShowAttachMenu(false);
    try {
      // Request screenshot with base64 data
      const response = await fetch('http://127.0.0.1:4850/capture?format=base64');
      if (response.ok) {
        const data = await response.json();
        if (data.base64) {
          setPendingImages(prev => [...prev, {
            type: 'base64',
            media_type: 'image/png',
            data: data.base64,
            name: 'screenshot.png'
          }]);
        }
      }
    } catch (error) {
      console.error('Screenshot error:', error);
    }
  };

  const addImage = () => {
    setShowAttachMenu(false);
    fileInputRef.current?.click();
  };

  const handleFileSelect = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;

    const reader = new FileReader();
    reader.onload = () => {
      const base64 = (reader.result as string).split(',')[1];
      const mediaType = file.type as ImageAttachment['media_type'];
      setPendingImages(prev => [...prev, {
        type: 'base64',
        media_type: mediaType || 'image/png',
        data: base64,
        name: file.name
      }]);
    };
    reader.readAsDataURL(file);
    e.target.value = ''; // Reset for next selection
  };

  const removeImage = (index: number) => {
    setPendingImages(prev => prev.filter((_, i) => i !== index));
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
              <div className="status-indicator">
                <span className="typing-spinner" />
                <span className="typing-label">{currentTool || 'Thinking...'}</span>
              </div>
            )}
            <div ref={messagesEndRef} />
          </div>
        )}
      </div>

      {/* Hidden file input */}
      <input
        ref={fileInputRef}
        type="file"
        accept="image/*"
        onChange={handleFileSelect}
        style={{ display: 'none' }}
      />

      {/* Input */}
      <div className="input-container">
        <div className={`input-wrapper ${isFocused ? 'focused' : ''} ${input.trim() || pendingImages.length > 0 ? 'has-content' : ''}`}>
          <textarea
            ref={textareaRef}
            value={input}
            onChange={e => setInput(e.target.value)}
            onKeyDown={handleKeyDown}
            onFocus={() => setIsFocused(true)}
            onBlur={() => setIsFocused(false)}
            placeholder="Message Bakable..."
            rows={1}
          />

          {/* Image previews */}
          {pendingImages.length > 0 && (
            <div className="image-previews">
              {pendingImages.map((img, index) => (
                <div key={index} className="image-preview">
                  <img src={`data:${img.media_type};base64,${img.data}`} alt={img.name || 'attachment'} />
                  <button className="remove-image" onClick={() => removeImage(index)}>
                    <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                      <line x1="18" y1="6" x2="6" y2="18" />
                      <line x1="6" y1="6" x2="18" y2="18" />
                    </svg>
                  </button>
                </div>
              ))}
            </div>
          )}

          <div className="input-bottom-row">
            <div className="mode-selector" ref={modeMenuRef}>
              <button
                className="mode-trigger"
                onClick={() => setShowModeMenu(!showModeMenu)}
              >
                {yoloMode ? (
                  <>
                    <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                      <polygon points="13 2 3 14 12 14 11 22 21 10 12 10 13 2" />
                    </svg>
                    <span>Auto-apply</span>
                  </>
                ) : (
                  <>
                    <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                      <circle cx="12" cy="12" r="10" />
                      <path d="M9.09 9a3 3 0 0 1 5.83 1c0 2-3 3-3 3" />
                      <line x1="12" y1="17" x2="12.01" y2="17" />
                    </svg>
                    <span>Confirm changes</span>
                  </>
                )}
                <svg width="10" height="10" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5">
                  <polyline points="6 9 12 15 18 9" />
                </svg>
              </button>

              {showModeMenu && (
                <div className="mode-menu">
                  <button
                    className={`mode-option ${!yoloMode ? 'selected' : ''}`}
                    onClick={() => { if (yoloMode) onToggleYolo(); setShowModeMenu(false); }}
                  >
                    <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                      <circle cx="12" cy="12" r="10" />
                      <path d="M9.09 9a3 3 0 0 1 5.83 1c0 2-3 3-3 3" />
                      <line x1="12" y1="17" x2="12.01" y2="17" />
                    </svg>
                    <div className="mode-info">
                      <span className="mode-title">Confirm changes</span>
                      <span className="mode-desc">Review and approve each change before it's applied</span>
                    </div>
                    {!yoloMode && (
                      <svg className="check-icon" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5">
                        <polyline points="20 6 9 17 4 12" />
                      </svg>
                    )}
                  </button>
                  <button
                    className={`mode-option ${yoloMode ? 'selected' : ''}`}
                    onClick={() => { if (!yoloMode) onToggleYolo(); setShowModeMenu(false); }}
                  >
                    <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                      <polygon points="13 2 3 14 12 14 11 22 21 10 12 10 13 2" />
                    </svg>
                    <div className="mode-info">
                      <span className="mode-title">Auto-apply</span>
                      <span className="mode-desc">Apply changes directly without confirmation prompts</span>
                    </div>
                    {yoloMode && (
                      <svg className="check-icon" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5">
                        <polyline points="20 6 9 17 4 12" />
                      </svg>
                    )}
                  </button>
                </div>
              )}
            </div>

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

              <div className="attach-selector" ref={attachMenuRef}>
                <button
                  className="action-btn attach-trigger"
                  onClick={() => setShowAttachMenu(!showAttachMenu)}
                  aria-label="Add attachment"
                >
                  <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                    <line x1="12" y1="5" x2="12" y2="19" />
                    <line x1="5" y1="12" x2="19" y2="12" />
                  </svg>
                </button>

                {showAttachMenu && (
                  <div className="attach-menu">
                    <button className="attach-option" onClick={takeScreenshot}>
                      <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                        <path d="M23 19a2 2 0 0 1-2 2H3a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h4l2-3h6l2 3h4a2 2 0 0 1 2 2z" />
                        <circle cx="12" cy="13" r="4" />
                      </svg>
                      <span>Take a screenshot</span>
                    </button>
                    <button className="attach-option" onClick={addImage}>
                      <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                        <rect x="3" y="3" width="18" height="18" rx="2" ry="2" />
                        <circle cx="8.5" cy="8.5" r="1.5" />
                        <polyline points="21 15 16 10 5 21" />
                      </svg>
                      <span>Add an image</span>
                    </button>
                  </div>
                )}
              </div>

              {isLoading ? (
                <button
                  className="action-btn stop-btn"
                  onClick={onCancel}
                  aria-label="Stop"
                >
                  <svg width="18" height="18" viewBox="0 0 24 24" fill="currentColor">
                    <rect x="6" y="6" width="12" height="12" rx="2" />
                  </svg>
                </button>
              ) : (
                <button
                  className={`action-btn send-btn ${input.trim() ? 'active' : ''}`}
                  onClick={handleSend}
                  disabled={!input.trim()}
                  aria-label="Send message"
                >
                  <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                    <path d="M5 12h14M12 5l7 7-7 7" />
                  </svg>
                </button>
              )}
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}
