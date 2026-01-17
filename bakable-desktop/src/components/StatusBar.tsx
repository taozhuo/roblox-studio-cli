import type { Session } from '../App';
import './StatusBar.css';

interface StatusBarProps {
  daemonConnected: boolean;
  editorConnected: boolean;
  activeEditor: string;
  session?: Session | null;
}

export default function StatusBar({
  daemonConnected,
  editorConnected,
  activeEditor,
  session
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
        {session && (
          <>
            <div className="status-divider" />
            <div className="status-indicator session-info">
              <span className="status-text session-name">{session.placeName}</span>
              {session.isPublished && (
                <span className="session-id">#{session.placeId}</span>
              )}
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
