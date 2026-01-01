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

  const getName = () => {
    if (isUser) return 'You';
    if (isSystem) return 'System';
    return 'Bakable';
  };

  const getAvatar = () => {
    if (isUser) return 'Y';
    if (isSystem) return '!';
    return (
      <svg width="14" height="14" viewBox="0 0 32 32" fill="none">
        <path d="M16 3L28 9.5V22.5L16 29L4 22.5V9.5L16 3Z" fill="white" />
      </svg>
    );
  };

  return (
    <div className={`message ${message.role} ${isLast ? 'last' : ''}`}>
      <div className="message-avatar">
        {getAvatar()}
      </div>

      <div className="message-body">
        <div className="message-header">
          <span className="message-name">{getName()}</span>
          <time className="message-time">
            {message.timestamp.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}
          </time>
        </div>

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
                              <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                                <polyline points="20 6 9 17 4 12" />
                              </svg>
                              Copied
                            </>
                          ) : (
                            <>
                              <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
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
      </div>
    </div>
  );
}
