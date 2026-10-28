// Module resolution patterns with various import/export styles

// Relative imports
import { User, AuthService } from './auth';
import { Database, UserData, UserSettings } from './database';
import * as Advanced from './advanced-patterns';

// Absolute path imports (simulating monorepo structure)
import { Config } from '@/config';
import { Logger } from '@utils/logger';
import { HttpClient } from '@http/client';

// Dynamic imports with type assertions
const loadConfig = async (): Promise<Config> => {
    const configModule = await import('@/config') as typeof import('@/config');
    return configModule.Config;
};

// Re-export patterns
export type { User, UserData, UserSettings } from './database';
export { Database, AuthService } from './database';
export { default as AdvancedPatterns } from './advanced-patterns';

// Namespace import with selective re-export
import * as HttpModule from '@http/client';
export { HttpModule.HttpClient as HttpClient };

// Export all from another module
export * from './auth';

// Mixed export patterns
export const DEFAULT_TIMEOUT = 5000;
export type RequestMethod = 'GET' | 'POST' | 'PUT' | 'DELETE';

export interface ApiClient {
    request<T>(method: RequestMethod, url: string, data?: any): Promise<T>;
    get<T>(url: string): Promise<T>;
    post<T>(url: string, data?: any): Promise<T>;
}

// Class that uses imported modules
export class UserService {
    private db: Database;
    private auth: AuthService;
    private http: HttpClient;
    private logger: Logger;

    constructor() {
        this.db = new Database();
        this.auth = new AuthService();
        this.http = new HttpClient({ timeout: DEFAULT_TIMEOUT });
        this.logger = new Logger('UserService');
    }

    async getUserById(id: number): Promise<User | null> {
        this.logger.info(`Fetching user ${id}`);
        
        try {
            // Use database service
            const userData = await this.db.queryUser(id);
            
            if (userData) {
                // Transform to User type
                const user: User = {
                    id: userData.id,
                    name: '', // Would be populated from userData
                    email: userData.id.toString() + '@example.com'
                };
                
                return user;
            }
            
            return null;
        } catch (error) {
            this.logger.error('Failed to fetch user', error);
            throw error;
        }
    }

    async authenticateUser(username: string, password: string): Promise<User> {
        return this.auth.authenticate(username, password);
    }

    async syncUserWithApi(userId: number): Promise<void> {
        const user = await this.getUserById(userId);
        if (!user) {
            throw new Error('User not found');
        }

        // Sync with external API
        await this.http.post('/api/users/sync', { userId: user.id });
    }
}

// Factory function using imports
export function createUserService(): UserService {
    return new UserService();
}

// Async function using dynamic imports
export async function loadAdvancedFeatures(): Promise<void> {
    const advanced = await import('./advanced-patterns');
    const patterns = new advanced.default();
    
    // Use the advanced patterns
    const result = patterns.processData('test');
    console.log('Advanced patterns result:', result);
}