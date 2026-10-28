import { authenticate, User } from './auth';
import { Database, UserData } from './database';

async function main(): Promise<void> {
    const username = process.argv[2];
    const password = process.argv[3];

    if (!username || !password) {
        console.error('Usage: npm start <username> <password>');
        process.exit(1);
    }

    // Initialize database
    const db = new Database();
    
    try {
        // Authenticate user
        const user = await authenticate(username, password);
        console.log(`Authenticated user: ${user.name}`);
        
        // Run application
        await runApp(db, user);
    } catch (error) {
        console.error('Authentication failed:', error);
        process.exit(1);
    } finally {
        await db.cleanup();
    }
}

async function runApp(db: Database, user: User): Promise<void> {
    const data = await db.queryUser(user.id);
    console.log(`User ID: ${data.id}`);
    console.log(`Theme: ${data.settings.theme}`);
}

if (require.main === module) {
    main().catch(console.error);
}

export { main, runApp };