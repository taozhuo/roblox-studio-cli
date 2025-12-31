import { useState } from 'react';
import ReactMarkdown from 'react-markdown';
import type { Message } from '../App';
import './MessageBubble.css';

interface MessageBubbleProps {
  message: Message;
  isLast?: boolean;
}

export default function MessageBubble({ message, isLast }: MessageBubbleProps) {
  const [copied, setCopied] = useState(false);
  const isUser = message.role === 'user';
  const isSystem = message.role === 'system';

  const copyToClipboard = async (text: string) => {
    await navigator.clipboard.writeText(text);
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  };

  return (
    <div className={`message ${message.role} ${isLast ? 'last' : ''}`}>
      {!isUser && (
        <div className={`message-avatar ${isSystem ? 'system' : ''}`}>
          {isSystem ? (
            <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round">
              <circle cx="12" cy="12" r="10" />
              <line x1="12" y1="8" x2="12" y2="12" />
              <line x1="12" y1="16" x2="12.01" y2="16" />
            </svg>
          ) : (
            <svg width="14" height="14" viewBox="0 0 32 32" fill="none">
              <path d="M16 3L28 9.5V22.5L16 29L4 22.5V9.5L16 3Z" fill="white" />
            </svg>
          )}
        </div>
      )}

      <div className="message-body">
        <div className="message-content">
          {isUser ? (
            <p>{message.content}</p>
          ) : (
            <ReactMarkdown
              components={{
                p: ({ children }) => <p>{children}</p>,
                code({ className, children, ...props }) {
                  const match = /language-(\w+)/.exec(className || '');
                  const isInline = !match && !className;
                  const codeText = String(children).replace(/\n$/, '');

                  if (isInline) {
                    return <code className="inline-code" {...props}>{children}</code>;
                  }

                  return (
                    <div className="code-block">
                      <div className="code-header">
                        <span className="code-lang">{match?.[1] || 'code'}</span>
                        <button
                          className="copy-btn"
                          onClick={() => copyToClipboard(codeText)}
                          aria-label="Copy code"
                        >
                          {copied ? (
                            <>
                              <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                                <polyline points="20 6 9 17 4 12" />
                              </svg>
                              Copied
                            </>
                          ) : (
                            <>
                              <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                                <rect x="9" y="9" width="13" height="13" rx="2" ry="2" />
                                <path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1" />
                              </svg>
                              Copy
                            </>
                          )}
                        </button>
                      </div>
                      <pre><code {...props}>{children}</code></pre>
                    </div>
                  );
                },
                a: ({ href, children }) => (
                  <a href={href} target="_blank" rel="noopener noreferrer">{children}</a>
                ),
                ul: ({ children }) => <ul>{children}</ul>,
                ol: ({ children }) => <ol>{children}</ol>,
                li: ({ children }) => <li>{children}</li>,
                strong: ({ children }) => <strong>{children}</strong>,
                em: ({ children }) => <em>{children}</em>,
                blockquote: ({ children }) => <blockquote>{children}</blockquote>,
              }}
            >
              {message.content}
            </ReactMarkdown>
          )}
        </div>

        <time className="message-time">
          {message.timestamp.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}
        </time>
      </div>
    </div>
  );
}
