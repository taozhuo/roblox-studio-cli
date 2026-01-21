import { TodoItem } from '../App';
import './TodoPanel.css';

interface TodoPanelProps {
  todos: TodoItem[];
  onClose: () => void;
}

export default function TodoPanel({ todos, onClose }: TodoPanelProps) {
  if (todos.length === 0) return null;

  const inProgress = todos.filter(t => t.status === 'in_progress');
  const pending = todos.filter(t => t.status === 'pending');
  const completed = todos.filter(t => t.status === 'completed');

  const getStatusIcon = (status: string) => {
    switch (status) {
      case 'completed': return '✓';
      case 'in_progress': return '●';
      default: return '○';
    }
  };

  const getStatusClass = (status: string) => {
    switch (status) {
      case 'completed': return 'todo-completed';
      case 'in_progress': return 'todo-in-progress';
      default: return 'todo-pending';
    }
  };

  return (
    <div className="todo-panel">
      <div className="todo-header">
        <span className="todo-title">Tasks ({completed.length}/{todos.length})</span>
        <button className="todo-close" onClick={onClose}>×</button>
      </div>
      <div className="todo-list">
        {inProgress.map((todo, i) => (
          <div key={`ip-${i}`} className={`todo-item ${getStatusClass(todo.status)}`}>
            <span className="todo-icon">{getStatusIcon(todo.status)}</span>
            <span className="todo-content">{todo.activeForm || todo.content}</span>
          </div>
        ))}
        {pending.map((todo, i) => (
          <div key={`p-${i}`} className={`todo-item ${getStatusClass(todo.status)}`}>
            <span className="todo-icon">{getStatusIcon(todo.status)}</span>
            <span className="todo-content">{todo.content}</span>
          </div>
        ))}
        {completed.map((todo, i) => (
          <div key={`c-${i}`} className={`todo-item ${getStatusClass(todo.status)}`}>
            <span className="todo-icon">{getStatusIcon(todo.status)}</span>
            <span className="todo-content">{todo.content}</span>
          </div>
        ))}
      </div>
    </div>
  );
}
