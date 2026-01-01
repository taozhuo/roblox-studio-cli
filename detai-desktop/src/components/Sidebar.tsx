import type { EditorConnection } from '../App';
import './Sidebar.css';

interface SidebarProps {
  open: boolean;
  onClose: () => void;
  editors: EditorConnection[];
  activeEditor: string;
  onSelectEditor: (name: string) => void;
  onClearChat?: () => void;
}

const editorConfig: Record<string, { icon: JSX.Element; color: string }> = {
  roblox: {
    icon: (
      <svg width="20" height="20" viewBox="0 0 24 24" fill="currentColor">
        <path d="M5.164 0L0 18.576l18.836 5.424L24 5.424zM13.637 16.05l-5.687-1.638 1.638-5.687 5.687 1.638z" />
      </svg>
    ),
    color: '#e2231a'
  },
  godot: {
    icon: (
      <svg width="20" height="20" viewBox="0 0 24 24" fill="currentColor">
        <path d="M12 0C5.372 0 0 5.372 0 12s5.372 12 12 12 12-5.372 12-12S18.628 0 12 0zm0 2c5.523 0 10 4.477 10 10s-4.477 10-10 10S2 17.523 2 12 6.477 2 12 2z" />
      </svg>
    ),
    color: '#478cbf'
  },
  unity: {
    icon: (
      <svg width="20" height="20" viewBox="0 0 24 24" fill="currentColor">
        <path d="M12.541 1.01L1.01 6.287l2.86 5.015-2.86 5.015L12.541 21.59v-5.015l-5.72-4.277 5.72-4.277V1.01z" />
      </svg>
    ),
    color: '#000000'
  },
  generic: {
    icon: (
      <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
        <polyline points="16 18 22 12 16 6" />
        <polyline points="8 6 2 12 8 18" />
      </svg>
    ),
    color: '#6366f1'
  }
};

export default function Sidebar({
  open,
  onClose,
  editors,
  activeEditor,
  onSelectEditor,
  onClearChat
}: SidebarProps) {
  return (
    <>
      <div className={`sidebar-backdrop ${open ? 'open' : ''}`} onClick={onClose} />

      <aside className={`sidebar ${open ? 'open' : ''}`}>
        {/* Header */}
        <header className="sidebar-header">
          <div className="sidebar-brand">
            <div className="sidebar-logo">
              <svg width="20" height="20" viewBox="0 0 32 32" fill="none">
                <defs>
                  <linearGradient id="sidebar-logo-gradient" x1="0%" y1="0%" x2="100%" y2="100%">
                    <stop offset="0%" stopColor="#818cf8" />
                    <stop offset="100%" stopColor="#6366f1" />
                  </linearGradient>
                </defs>
                <path d="M16 3L28 9.5V22.5L16 29L4 22.5V9.5L16 3Z" fill="url(#sidebar-logo-gradient)" />
              </svg>
            </div>
            <div>
              <h1 className="sidebar-title">DetAI</h1>
              <p className="sidebar-version">v0.1.0</p>
            </div>
          </div>
          <button className="sidebar-close" onClick={onClose} aria-label="Close sidebar">
            <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
              <line x1="18" y1="6" x2="6" y2="18" />
              <line x1="6" y1="6" x2="18" y2="18" />
            </svg>
          </button>
        </header>

        {/* Content */}
        <div className="sidebar-content">
          {/* Editors */}
          <section className="sidebar-section">
            <h2 className="section-title">Editors</h2>
            <div className="editor-grid">
              {editors.map(editor => {
                const config = editorConfig[editor.type] || editorConfig.generic;
                const isActive = activeEditor === editor.name;

                return (
                  <button
                    key={editor.name}
                    className={`editor-card ${isActive ? 'active' : ''} ${editor.connected ? 'connected' : ''}`}
                    onClick={() => {
                      onSelectEditor(editor.name);
                      onClose();
                    }}
                  >
                    <div className="editor-icon" style={{ color: config.color }}>
                      {config.icon}
                    </div>
                    <span className="editor-name">{editor.name}</span>
                    <span className={`editor-status ${editor.connected ? 'connected' : ''}`}>
                      {editor.connected ? 'Connected' : 'Offline'}
                    </span>
                  </button>
                );
              })}

              <button className="editor-card add-editor" disabled>
                <div className="editor-icon">
                  <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                    <line x1="12" y1="5" x2="12" y2="19" />
                    <line x1="5" y1="12" x2="19" y2="12" />
                  </svg>
                </div>
                <span className="editor-name">Add Editor</span>
                <span className="editor-status">Coming Soon</span>
              </button>
            </div>
          </section>

          {/* Actions */}
          <section className="sidebar-section">
            <h2 className="section-title">Actions</h2>
            <button className="action-card" onClick={() => { onClearChat?.(); onClose(); }}>
              <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                <polyline points="3 6 5 6 21 6" />
                <path d="M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6m3 0V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2" />
              </svg>
              Clear Chat
            </button>
          </section>

          {/* Connection */}
          <section className="sidebar-section">
            <h2 className="section-title">Connection</h2>
            <div className="info-card">
              <div className="info-row">
                <span className="info-label">Daemon</span>
                <span className="info-value">localhost:4849</span>
              </div>
              <div className="info-row">
                <span className="info-label">Helper</span>
                <span className="info-value">localhost:4850</span>
              </div>
            </div>
          </section>
        </div>

        {/* Footer */}
        <footer className="sidebar-footer">
          <a href="https://detai.dev" target="_blank" rel="noopener noreferrer" className="footer-link">
            <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
              <circle cx="12" cy="12" r="10" />
              <line x1="2" y1="12" x2="22" y2="12" />
              <path d="M12 2a15.3 15.3 0 0 1 4 10 15.3 15.3 0 0 1-4 10 15.3 15.3 0 0 1-4-10 15.3 15.3 0 0 1 4-10z" />
            </svg>
            detai.dev
          </a>
          <a href="https://github.com/detai" target="_blank" rel="noopener noreferrer" className="footer-link">
            <svg width="14" height="14" viewBox="0 0 24 24" fill="currentColor">
              <path d="M12 0C5.37 0 0 5.37 0 12c0 5.31 3.435 9.795 8.205 11.385.6.105.825-.255.825-.57 0-.285-.015-1.23-.015-2.235-3.015.555-3.795-.735-4.035-1.41-.135-.345-.72-1.41-1.23-1.695-.42-.225-1.02-.78-.015-.795.945-.015 1.62.87 1.845 1.23 1.08 1.815 2.805 1.305 3.495.99.105-.78.42-1.305.765-1.605-2.67-.3-5.46-1.335-5.46-5.925 0-1.305.465-2.385 1.23-3.225-.12-.3-.54-1.53.12-3.18 0 0 1.005-.315 3.3 1.23.96-.27 1.98-.405 3-.405s2.04.135 3 .405c2.295-1.56 3.3-1.23 3.3-1.23.66 1.65.24 2.88.12 3.18.765.84 1.23 1.905 1.23 3.225 0 4.605-2.805 5.625-5.475 5.925.435.375.81 1.095.81 2.22 0 1.605-.015 2.895-.015 3.3 0 .315.225.69.825.57A12.02 12.02 0 0024 12c0-6.63-5.37-12-12-12z" />
            </svg>
            GitHub
          </a>
        </footer>
      </aside>
    </>
  );
}
