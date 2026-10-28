// Frontend authentication module
import { DatabaseConnection } from './database';

export interface User {
  id: number;
  name: string;
  email: string;
}

export interface AuthResponse {
  success: boolean;
  user?: User;
  token?: string;
  error?: string;
}

export class AuthenticationService {
  private db: DatabaseConnection;
  private sessions: Map<string, User> = new Map();

  constructor(db: DatabaseConnection) {
    this.db = db;
  }

  async authenticate(username: string, password: string): Promise<AuthResponse> {
    try {
      // Mock authentication - in real implementation would call backend
      if (username === 'admin' && password === 'password') {
        const user: User = {
          id: 1,
          name: 'Admin User',
          email: 'admin@example.com'
        };
        
        const token = this.generateSessionToken(user);
        this.sessions.set(token, user);
        
        return {
          success: true,
          user,
          token
        };
      }
      
      if (username === 'user' && password === 'pass') {
        const user: User = {
          id: 2,
          name: 'Regular User',
          email: 'user@example.com'
        };
        
        const token = this.generateSessionToken(user);
        this.sessions.set(token, user);
        
        return {
          success: true,
          user,
          token
        };
      }
      
      return {
        success: false,
        error: 'Invalid credentials'
      };
    } catch (error) {
      return {
        success: false,
        error: error instanceof Error ? error.message : 'Authentication failed'
      };
    }
  }

  async validateSession(token: string): Promise<boolean> {
    return this.sessions.has(token);
  }

  async logout(token: string): Promise<void> {
    this.sessions.delete(token);
  }

  private generateSessionToken(user: User): string {
    return `session_${user.id}_${Date.now()}`;
  }
}