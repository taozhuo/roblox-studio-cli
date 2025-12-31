import './StatusBar.css';

interface StatusBarProps {
  daemonConnected: boolean;
  editorConnected: boolean;
  activeEditor: string;
  currentTool?: string | null;
}

export default function StatusBar({
  daemonConnected,
  editorConnected,
  activeEditor,
  currentTool
}: StatusBarProps) {
  return (
    <footer className="status-bar">
      <div className="status-left">
        <div className={`status-indicator ${daemonConnected ? 'connected' : ''}`}>
          <span className="status-dot" />
          <span className="status-text">Daemon</span>
        </div>
        <div className="status-divider" />
        <div className={`status-indicator ${editorConnected ? 'connected' : ''}`}>
          <span className="status-dot" />
          <span className="status-text">{activeEditor}</span>
        </div>
        {currentTool && (
          <>
            <div className="status-divider" />
            <div className="status-indicator tool-active">
              <span className="status-text tool-text">{currentTool}</span>
            </div>
          </>
        )}
      </div>

      <div className="status-right">
        <span className="status-hint">
          <kbd>⌘</kbd><kbd>K</kbd> Commands
        </span>
      </div>
    </footer>
  );
}
