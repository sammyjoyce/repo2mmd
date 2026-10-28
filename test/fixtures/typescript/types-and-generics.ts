// Comprehensive type definitions and generic patterns

// Basic and advanced types
type ID = string | number;
type Timestamp = number;
type JsonValue = string | number | boolean | null | JsonObject | JsonArray;
interface JsonObject {
    [key: string]: JsonValue;
}
type JsonArray = JsonValue[];

// Generic interfaces
interface ApiResponse<T> {
    data: T;
    status: number;
    message: string;
    timestamp: Timestamp;
}

interface PaginatedResponse<T> extends ApiResponse<T[]> {
    pagination: {
        page: number;
        limit: number;
        total: number;
        hasNext: boolean;
    };
}

// Generic classes
class Collection<T> {
    private items: T[] = [];

    constructor(items: T[] = []) {
        this.items = [...items];
    }

    add(item: T): void {
        this.items.push(item);
    }

    remove(predicate: (item: T) => boolean): T | null {
        const index = this.items.findIndex(predicate);
        if (index >= 0) {
            return this.items.splice(index, 1)[0];
        }
        return null;
    }

    find(predicate: (item: T) => boolean): T | undefined {
        return this.items.find(predicate);
    }

    filter(predicate: (item: T) => boolean): Collection<T> {
        return new Collection(this.items.filter(predicate));
    }

    map<U>(mapper: (item: T) => U): Collection<U> {
        return new Collection(this.items.map(mapper));
    }

    get size(): number {
        return this.items.length;
    }

    toArray(): T[] {
        return [...this.items];
    }
}

// Utility types
type Partial<T> = {
    [P in keyof T]?: T[P];
};

type Required<T> = {
    [P in keyof T]-?: T[P];
};

type Readonly<T> = {
    readonly [P in keyof T]: T[P];
};

// Conditional types
type NonNullable<T> = T extends null | undefined ? never : T;
type Flatten<T> = T extends (infer U)[] ? U : T;

// Mapped types with constraints
type StringKeys<T> = {
    [K in keyof T]: K extends string ? K : never;
}[keyof T];

// Function types
type Predicate<T> = (value: T) => boolean;
type Mapper<T, U> = (value: T) => U;
type Reducer<T, U> = (accumulator: U, value: T) => U;

// Generic functions
function createApiResponse<T>(data: T, message: string = 'Success'): ApiResponse<T> {
    return {
        data,
        status: 200,
        message,
        timestamp: Date.now()
    };
}

function pipe<T, U, V>(fn1: Mapper<T, U>, fn2: Mapper<U, V>): Mapper<T, V> {
    return (value: T) => fn2(fn1(value));
}

function curry<T, U, V>(fn: (a: T, b: U) => V): (a: T) => (b: U) => V {
    return (a: T) => (b: U) => fn(a, b);
}

// Generic constraints
interface Identifiable {
    id: ID;
}

function findById<T extends Identifiable>(collection: Collection<T>, id: ID): T | undefined {
    return collection.find(item => item.id === id);
}

// Variadic tuple types
function tuple<T extends unknown[]>(...args: T): T {
    return args;
}

// Template literal types
type EventName<T extends string> = `on${Capitalize<T>}`;
type EventHandler<T extends string> = (event: EventName<T>) => void;

// Branded types
type Brand<T, B> = T & { __brand: B };
type UserId = Brand<string, 'UserId'>;
type EmailAddress = Brand<string, 'EmailAddress'>;

function createUserId(id: string): UserId {
    return id as UserId;
}

function createEmail(email: string): EmailAddress {
    if (!email.includes('@')) {
        throw new Error('Invalid email format');
    }
    return email as EmailAddress;
}

// Generic classes with multiple type parameters
class Cache<K, V> {
    private cache = new Map<K, V>();

    constructor(private maxSize: number = 100) {}

    set(key: K, value: V): void {
        if (this.cache.size >= this.maxSize) {
            const firstKey = this.cache.keys().next().value;
            this.cache.delete(firstKey);
        }
        this.cache.set(key, value);
    }

    get(key: K): V | undefined {
        return this.cache.get(key);
    }

    has(key: K): boolean {
        return this.cache.has(key);
    }

    clear(): void {
        this.cache.clear();
    }

    get size(): number {
        return this.cache.size;
    }
}

// Export examples
export type {
    ApiResponse,
    PaginatedResponse,
    JsonValue,
    JsonObject,
    JsonArray,
    UserId,
    EmailAddress
};

export {
    Collection,
    Cache,
    createApiResponse,
    pipe,
    curry,
    findById,
    createUserId,
    createEmail
};

// Default export
export default class TypeSystem {
    private userCache = new Cache<UserId, User>(50);
    private emailCache = new Cache<EmailAddress, string>(100);

    cacheUser(userId: UserId, user: User): void {
        this.userCache.set(userId, user);
    }

    getUser(userId: UserId): User | undefined {
        return this.userCache.get(userId);
    }

    cacheEmail(email: EmailAddress, data: string): void {
        this.emailCache.set(email, data);
    }

    getEmail(email: EmailAddress): string | undefined {
        return this.emailCache.get(email);
    }
}