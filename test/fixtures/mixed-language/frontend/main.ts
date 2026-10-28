// Frontend main application
import { AuthenticationService, AuthResponse, User } from './auth';
import { DatabaseConnection, DatabaseConfig } from './database';

class Application {
  private authService: AuthenticationService;
  private db: DatabaseConnection;

  constructor() {
    const dbConfig: DatabaseConfig = {
      host: 'localhost',
      port: 5432,
      database: 'app_db',
      username: 'app_user',
      password: 'app_password'
    };

    this.db = new DatabaseConnection(dbConfig);
    this.authService = new AuthenticationService(this.db);
  }

  async initialize(): Promise<void> {
    await this.db.connect();
    console.log('Application initialized');
  }

  async login(username: string, password: string): Promise<AuthResponse> {
    return this.authService.authenticate(username, password);
  }

  async logout(token: string): Promise<void> {
    await this.authService.logout(token);
  }

  async getCurrentUser(token: string): Promise<User | null> {
    const isValid = await this.authService.validateSession(token);
    if (!isValid) {
      return null;
    }

    // In a real implementation, would get user from session
    // For mock purposes, return admin user
    return {
      id: 1,
      name: 'Admin User',
      email: 'admin@example.com'
    };
  }

  async shutdown(): Promise<void> {
    await this.db.disconnect();
    console.log('Application shutdown');
  }
}

// Application entry point
async function main(): Promise<void> {
  const app = new Application();
  
  try {
    await app.initialize();
    
    // Example usage
    const authResult = await app.login('admin', 'password');
    if (authResult.success && authResult.token) {
      console.log(`Login successful: ${authResult.user?.name}`);
      
      const currentUser = await app.getCurrentUser(authResult.token);
      console.log(`Current user: ${currentUser?.name}`);
      
      await app.logout(authResult.token);
      console.log('Logged out successfully');
    } else {
      console.error(`Login failed: ${authResult.error}`);
    }
    
    await app.shutdown();
  } catch (error) {
    console.error('Application error:', error);
    process.exit(1);
  }
}

// Export for potential use in other modules
export { Application, main };

// Run main if this file is executed directly
if (require.main === module) {
  main();
}