import * as crypto from 'crypto';

export interface User {
    id: number;
    name: string;
    email: string;
}

export class AuthError extends Error {
    constructor(
        message: string,
        public code: 'INVALID_CREDENTIALS' | 'USER_NOT_FOUND' | 'DATABASE_ERROR'
    ) {
        super(message);
        this.name = 'AuthError';
    }
}

export async function authenticate(username: string, password: string): Promise<User> {
    // Mock authentication - in real implementation would query database
    if (username === 'admin' && password === 'password') {
        return {
            id: 1,
            name: 'Admin User',
            email: 'admin@example.com'
        };
    }
    
    throw new AuthError('Invalid credentials', 'INVALID_CREDENTIALS');
}

export function hashPassword(password: string): string {
    return crypto.createHash('sha256').update(password).digest('hex');
}

export function verifyPassword(password: string, hash: string): boolean {
    const computed = hashPassword(password);
    return computed === hash;
}

export class AuthService {
    private users: Map<string, User> = new Map();
    
    constructor() {
        // Initialize with mock user
        this.users.set('admin', {
            id: 1,
            name: 'Admin User',
            email: 'admin@example.com'
        });
    }
    
    async authenticate(username: string, password: string): Promise<User> {
        const user = this.users.get(username);
        if (!user) {
            throw new AuthError('User not found', 'USER_NOT_FOUND');
        }
        
        // Simple password check for demo
        if (username === 'admin' && password === 'password') {
            return user;
        }
        
        throw new AuthError('Invalid credentials', 'INVALID_CREDENTIALS');
    }
}