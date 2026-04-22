use std::collections::HashMap;

use crossbeam_channel::{Sender, Receiver, bounded};
use parking_lot::RwLock;

/// Event types emitted by the reactive system
#[derive(Debug, Clone)]
pub enum StoreEvent {
    /// A record was inserted
    Insert {
        collection: String,
        id: String,
        data: Vec<u8>,
    },
    /// A record was updated
    Update {
        collection: String,
        id: String,
        data: Vec<u8>,
    },
    /// A record was deleted
    Delete {
        collection: String,
        id: String,
    },
}

impl StoreEvent {
    /// Get the collection name from the event
    pub fn collection(&self) -> &str {
        match self {
            StoreEvent::Insert { collection, .. } => collection,
            StoreEvent::Update { collection, .. } => collection,
            StoreEvent::Delete { collection, .. } => collection,
        }
    }

    /// Get the record ID from the event
    pub fn id(&self) -> &str {
        match self {
            StoreEvent::Insert { id, .. } => id,
            StoreEvent::Update { id, .. } => id,
            StoreEvent::Delete { id, .. } => id,
        }
    }
}

/// Subscription handle for a watcher
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub struct SubscriptionId(u64);

/// A watcher subscription
struct Subscription {
    /// Channel sender for events
    sender: Sender<StoreEvent>,
    /// Collection being watched
    collection: String,
}

/// Reactive watcher system
///
/// Manages subscriptions to collection changes and broadcasts
/// events to all active watchers.
pub struct WatcherSystem {
    /// Active subscriptions
    subscriptions: RwLock<HashMap<u64, Subscription>>,
    /// Next subscription ID
    next_id: RwLock<u64>,
}

impl WatcherSystem {
    /// Create a new watcher system
    pub fn new() -> Self {
        Self {
            subscriptions: RwLock::new(HashMap::new()),
            next_id: RwLock::new(0),
        }
    }

    /// Subscribe to events for a collection
    ///
    /// Returns a subscription ID and a receiver for events
    pub fn subscribe(&self, collection: &str) -> (u64, Receiver<StoreEvent>) {
        let (sender, receiver) = bounded(256);

        let mut next_id = self.next_id.write();
        let id = *next_id;
        *next_id += 1;

        let mut subs = self.subscriptions.write();
        subs.insert(
            id,
            Subscription {
                sender,
                collection: collection.to_string(),
            },
        );

        (id, receiver)
    }

    /// Unsubscribe from events
    pub fn unsubscribe(&self, subscription_id: u64) {
        let mut subs = self.subscriptions.write();
        subs.remove(&subscription_id);
    }

    /// Broadcast an event to all watchers of the affected collection
    pub fn notify(&self, event: StoreEvent) {
        let subs = self.subscriptions.read();
        for (_, subscription) in subs.iter() {
            if subscription.collection == event.collection() {
                // Non-blocking send - if channel is full, skip
                let _ = subscription.sender.try_send(event.clone());
            }
        }
    }

    /// Get the number of active subscriptions for a collection
    pub fn subscription_count(&self, collection: &str) -> usize {
        let subs = self.subscriptions.read();
        subs.values()
            .filter(|s| s.collection == collection)
            .count()
    }

    /// Unsubscribe all watchers for a collection
    pub fn clear_collection(&self, collection: &str) {
        let mut subs = self.subscriptions.write();
        subs.retain(|_, sub| sub.collection != collection);
    }

    /// Clear all subscriptions
    pub fn clear_all(&self) {
        let mut subs = self.subscriptions.write();
        subs.clear();
    }
}

impl Default for WatcherSystem {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_subscribe_and_notify() {
        let system = WatcherSystem::new();
        let (id, receiver) = system.subscribe("users");

        system.notify(StoreEvent::Insert {
            collection: "users".to_string(),
            id: "user_1".to_string(),
            data: vec![1, 2, 3],
        });

        let event = receiver.recv_timeout(std::time::Duration::from_millis(100));
        assert!(event.is_ok());

        system.unsubscribe(id);
        assert_eq!(system.subscription_count("users"), 0);
    }

    #[test]
    fn test_collection_filtering() {
        let system = WatcherSystem::new();
        let (_, receiver) = system.subscribe("users");

        // This event should not be received (different collection)
        system.notify(StoreEvent::Insert {
            collection: "products".to_string(),
            id: "prod_1".to_string(),
            data: vec![],
        });

        let result = receiver.recv_timeout(std::time::Duration::from_millis(50));
        assert!(result.is_err());
    }
}
