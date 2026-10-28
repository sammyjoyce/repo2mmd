import React, { useState, useEffect, useCallback } from 'react';
import { User } from './auth';
import { Database } from './database';

interface Props {
    userId: string;
    onUpdate?: (user: User) => void;
}

interface State {
    user: User | null;
    loading: boolean;
    error: string | null;
}

// Functional component with hooks
export const UserProfile: React.FC<Props> = ({ userId, onUpdate }) => {
    const [state, setState] = useState<State>({
        user: null,
        loading: true,
        error: null
    });

    // Custom hook for database operations
    const useDatabase = () => {
        const [db] = useState(() => new Database());
        
        useEffect(() => {
            db.init();
            return () => db.cleanup();
        }, [db]);
        
        return db;
    };

    const db = useDatabase();

    // Memoized callback
    const loadUser = useCallback(async () => {
        try {
            setState(prev => ({ ...prev, loading: true, error: null }));
            const user = await db.queryUser(parseInt(userId));
            setState(prev => ({ ...prev, user, loading: false }));
        } catch (err) {
            setState(prev => ({ 
                ...prev, 
                error: err instanceof Error ? err.message : 'Unknown error',
                loading: false 
            }));
        }
    }, [db, userId]);

    useEffect(() => {
        loadUser();
    }, [loadUser]);

    // Class component for comparison
    class UserCard extends React.Component<{ user: User }> {
        render() {
            const { user } = this.props;
            return (
                <div className="user-card">
                    <h3>{user.name}</h3>
                    <p>Email: {user.email}</p>
                    <p>ID: {user.id}</p>
                </div>
            );
        }
    }

    // Higher-order component
    const withLoading = <P extends object>(Component: React.ComponentType<P>) => {
        return (props: P & { loading: boolean }) => {
            if (props.loading) {
                return <div>Loading...</div>;
            }
            return <Component {...props as P} />;
        };
    };

    const UserCardWithLoading = withLoading(UserCard);

    if (state.loading) {
        return <div>Loading user profile...</div>;
    }

    if (state.error) {
        return <div>Error: {state.error}</div>;
    }

    if (!state.user) {
        return <div>User not found</div>;
    }

    return (
        <div className="user-profile">
            <UserCardWithLoading user={state.user} loading={false} />
            <button onClick={() => onUpdate?.(state.user!)}>
                Update User
            </button>
        </div>
    );
};

// JSX fragment example
export const FragmentExample: React.FC = () => {
    return (
        <>
            <h1>Fragment Example</h1>
            <p>This uses React fragments</p>
        </>
    );
};

// Custom component with generics
interface ListProps<T> {
    items: T[];
    renderItem: (item: T) => React.ReactNode;
}

export function GenericList<T>({ items, renderItem }: ListProps<T>) {
    return (
        <ul>
            {items.map((item, index) => (
                <li key={index}>{renderItem(item)}</li>
            ))}
        </ul>
    );
}